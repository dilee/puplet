# AGENTS.md

Guidance for coding agents working in this repository. Human contributors should read it too.

Puplet is a macOS desktop pet: a menu-bar agent (`LSUIElement`) that walks a procedurally-drawn
puppy around the bottom of the screen and can hold a conversation. Swift 6 toolchain, SwiftPM, no
third-party dependencies, AppKit + SpriteKit only. `README.md` documents the *why* behind the
window and brain design — read its "Design decisions worth keeping" section before changing either.

## Commands

```sh
make run                 # release build → build/Puplet.app → quit old instance → relaunch
make bundle              # build the .app without launching
make build               # plain `swift build`
make quit                # osascript quit of the running app
make frames              # render every pose to ./frames + contact-sheet.png (no app launch)
make gif                 # regenerate docs/demo.gif
make chat MSG="hi pup"   # exercise the chat ladder in the terminal, prints which layer answered
make clean
swift run Puplet         # unbundled; a Dock icon appears (LSUIElement only applies in the bundle)
```

There is **no test target**. Verification is manual: `make frames` for art, `make chat` for the
brain ladder, `make run` for behavior. Prefer the two headless modes — they skip `NSApplication`
entirely and are the fast loop.

`main.swift` intercepts `--dump-frames`, `--dump-gif`, and `--chat` before the app starts and
`exit(0)`s. Add new headless tools there.

## Architecture

### One tick, one window

`SKScene.update` → `PetScene.onFrame` → `PetController.step(dt)` is the only game loop. That single
function steps the behavior machine, polls the mouse gate, integrates gravity, moves the window,
and counts down the idle-thought timer. `dt` is clamped to 1/15 s so a stalled frame can't teleport
the pet.

The pet **is** a 96×96 borderless `NSPanel` that gets `setFrameOrigin`'d to walk around — not a
full-screen overlay. `PetPanel.swift` holds two panel recipes: `PetPanel` (interactive) and
`OverlayPanel` (permanently `ignoresMouseEvents`, used by the speech bubble).

Click-through is done by *polling*: `updateMouseGate()` compares `NSEvent.mouseLocation` against
`PetController.interactiveCore` each frame and toggles `panel.ignoresMouseEvents`. That rect is in
**canvas coordinates**, so it must be re-tuned if `CreatureRenderer.canvas` or the art's silhouette
changes. Don't replace this with a global event monitor or alpha hit-testing — both were rejected
for reasons the README explains.

The pet is pinned to one display via `homeScreenID`; only dragging and "Come Here" change screens.

### Art is code, and the pose lists are duplicated

`Pose` (a struct of animation parameters) → `CreatureRenderer.image(for:)` draws it procedurally
into an `NSImage` → `PetScene.buildAnimations()` rasterizes those to `SKTexture`s and builds one
`SKAction` loop per `PetState`. **All textures are baked once at scene init**, so poses must be
pure functions of a `Pose`.

Adding or changing a state means touching all of: `PetState` (`Behavior.swift`), the weighted
transition table and duration switch beside it, `buildAnimations()`, and — separately —
`FrameDumper.run()`, which keeps its **own copy** of the pose lists. The two drift silently; update
both.

### Two brain ladders that never block the body

Two protocols, deliberately separate:

- `PetBrain.line(for:context:)` — ambient banter (taps, app switches, idle thoughts). Free layers
  only: on-device `FoundationModelsBrain` → `CannedBrain`. Never touches the Claude subscription.
- `ChatBrain.chat` / `.chatStreaming` — user-initiated. `ClaudeCodeBrain` → on-device → canned
  shrug. `chatStreaming` has a protocol-extension default that falls back to `chat`, so a new layer
  only implements streaming if it can.

`LayeredBrain` implements `PetBrain` and owns both ladders plus the shared `PetMemory`. Its
`reply(to:)` **never returns nil** — the canned fallback is the floor. New layers go into
`chatLayers` in priority order.

**The brain never drives the body.** It returns a line and a mood string; `onMood` →
`PetController.apply(mood:)` nudges the state machine, and unrecognized moods are ignored. The
animation keeps running while generation is slow or failing. `PetController` gates speech with
`isGenerating`, `isChatting`, and a 20 s `canSpeakSpontaneously` throttle.

All prompts live in `PetPersona` (`Brain.swift`) — one `base(name:)` plus per-ladder wrappers, each
of which injects `memorySection`. Add prompt text there, not at call sites.

**Model text is never spoken raw.** Everything a model produces goes through `PetSpeech.clean`,
which strips roleplay stage directions (`*wags tail*`, `*sniffs*`): the sprite already shows the
action, so narrating it is noise. It also drops text following an unclosed `*`, which is what keeps
a half-streamed direction from flashing into the bubble mid-stream. A new brain layer must route its
output through it, and the persona forbids the behavior up front so the stripper is a safety net
rather than the primary defense.

### Memory

A single `PetMemory` instance is created by `LayeredBrain` and handed to every brain, so all layers
read the same facts. `NSLock`-guarded, `@unchecked Sendable`, capped at 60 facts, persisted
atomically to `~/Library/Application Support/Puplet/memory.json`. Two write paths: the on-device
`RememberTool` tool call, and the `remember` field of the Claude JSON contract. A one-time migration
from the old `AIPet/` support directory lives in `Memory.swift`.

### ClaudeCodeBrain

Shells out to the local `claude` CLI, riding the user's subscription — no API key. Details that are
load-bearing and easy to break:

- Launched as `/bin/zsh -l -c 'exec "$0" "$@"' <binary> <args…>`. The login shell is required: an
  app opened from Finder inherits almost no `PATH`. Binary resolution tries known paths, then
  `command -v claude`, on a background `Task` awaited at first use.
- `--tools ""` disables the entire toolset — the pet must never read files or run commands.
- `--system-prompt` (not `--bare`, which would skip the keychain OAuth this brain exists to use).
- `cwd` is the app-support directory, keeping pet sessions out of real project history.
- `--resume <session-id>` from the previous `result` envelope gives one conversation per app run.
- Streaming needs `--verbose` alongside `--output-format stream-json --include-partial-messages`;
  it's mandatory in print mode.
- The reply is a JSON contract `{"say", "mood", "remember"}`. `StreamAccumulator` accumulates text
  deltas and `partialSay(from:)` extracts the growing `say` value incrementally, so the bubble types
  words rather than JSON. Thinking deltas are dropped. `parseEnvelope` handles the final envelope
  for both the streaming and non-streaming paths.
- 75 s timeout; two consecutive failures flip `availability` to `.failing` and chat falls through to
  the next layer instead of hanging every message.

These flags track a CLI this repo doesn't vendor. Before changing any of them, check the installed
interface (`claude --help`) rather than assuming — and re-verify with `make chat`, which reports
which layer actually answered.

## Constraints to preserve

- **Zero TCC permissions.** `WorkspaceContext` uses only `NSWorkspace` notifications and the clock.
  Window titles (Accessibility) and pixels (Screen Recording) are deliberately absent; any new
  context source must stay opt-in.
- **No dependencies.** Everything is system frameworks.
- **`FoundationModels` is gated three ways**: `#if canImport`, `@available(macOS 26.0, *)`, and a
  runtime `SystemLanguageModel.default.availability` check. Keep all three.
- **Ambient chatter stays free.** Only user-initiated chat may reach a metered or subscription model.
- UI types are `@MainActor` (`PetController`, `AppDelegate`, `ChatInputController`, `PetSettings`);
  brains are not, and use `NSLock` + `@unchecked Sendable`. Package is Swift 6 tools with language
  mode v5.
- `UserDefaults` domain `dev.dilee.puplet`: `petName` via `PetSettings`, and `chatModel` /
  `chatEffort` read per-message directly in `ClaudeCodeBrain.buildArguments`.
- Renaming the `Puplet` target would also need `scripts/bundle.sh` and `CFBundleExecutable` in
  `Resources/Info.plist` updated.

## Code style

Default to no comments. Write one only when it states something the code cannot: the rationale for a
non-obvious choice, an invariant, a workaround and what forces it, or a perf/security caveat. Doc
comments on public declarations are welcome. The existing source is near-comment-free by intent —
match it.
