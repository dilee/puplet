#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/release.sh <version> [--skip-notarize]

Builds, signs, notarizes and staples build/Puplet.app, then writes the zip you
publish and a ready-to-commit Homebrew cask.

  <version>         semver for this release, e.g. 0.1.0 (no leading "v")
  --skip-notarize   sign and package only, never contacting Apple. Use it to
                    rehearse the pipeline, or before a Developer ID cert exists.

Environment:
  SIGN_IDENTITY     codesigning identity; defaults to the first
                    "Developer ID Application" identity in the keychain
  NOTARY_PROFILE    notarytool keychain profile (default: puplet-notary), created once with
                    xcrun notarytool store-credentials puplet-notary \
                      --apple-id <you> --team-id <TEAMID> --password <app-specific-password>
EOF
}

VERSION=""
SKIP_NOTARIZE=0
for arg in "$@"; do
  case "$arg" in
    --skip-notarize) SKIP_NOTARIZE=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown flag: $arg" >&2; echo >&2; usage >&2; exit 2 ;;
    *)
      if [[ -n "$VERSION" ]]; then
        echo "unexpected argument: $arg" >&2
        exit 2
      fi
      VERSION="$arg"
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  usage >&2
  exit 2
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.]+)?$ ]]; then
  echo "version should look like 1.2.3, got: $VERSION" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/build/Puplet.app"
ZIP="$ROOT/build/Puplet-$VERSION.zip"
CASK="$ROOT/build/puplet.rb"
NOTARY_PROFILE="${NOTARY_PROFILE:-puplet-notary}"
REPO="dilee/puplet"
TAP="dilee/homebrew-tap"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  if [[ "$SKIP_NOTARIZE" -eq 1 ]]; then
    echo "No Developer ID Application identity found — the rehearsal will keep the ad-hoc"
    echo "signature from bundle.sh. The resulting zip is NOT distributable."
  else
    cat >&2 <<'EOF'
No "Developer ID Application" identity in the keychain, so this build cannot be
notarized. Create one in Xcode → Settings → Accounts → your Apple ID → Manage
Certificates → + → Developer ID Application, then check it landed with:

  security find-identity -v -p codesigning

To rehearse everything except Apple's part, re-run with --skip-notarize.
EOF
    exit 1
  fi
fi

step "Building and bundling $VERSION"
./scripts/bundle.sh release "$VERSION"

if [[ -n "$SIGN_IDENTITY" ]]; then
  step "Signing with $SIGN_IDENTITY"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
fi

if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
  SUBMIT_ZIP="$ROOT/build/Puplet-submit.zip"
  step "Submitting to Apple (profile: $NOTARY_PROFILE) — this usually takes a few minutes"
  ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"
  xcrun notarytool submit "$SUBMIT_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  rm -f "$SUBMIT_ZIP"

  step "Stapling the notarization ticket"
  xcrun stapler staple "$APP"
fi

step "Packaging"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

step "Verifying the way a stranger's Mac will"
if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
  spctl -a -vvv -t install "$APP"
  xcrun stapler validate "$APP"
else
  codesign -dv --verbose=2 "$APP" 2>&1 | grep -E 'Signature|TeamIdentifier|flags' || true
  echo "(rehearsal: skipped spctl and stapler, which only pass on a notarized build)"
fi

cat > "$CASK" <<EOF
cask "puplet" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$REPO/releases/download/v#{version}/Puplet-#{version}.zip"
  name "Puplet"
  desc "Desktop pet with a layered AI brain"
  homepage "https://github.com/$REPO"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "Puplet.app"

  caveats <<~CAVEATS
    Chat rides your Claude subscription through the Claude Code CLI — install it and
    log in for full replies. Ambient banter uses Apple Intelligence on macOS 26.
    Without either, Puplet falls back to canned lines.
  CAVEATS

  zap trash: [
    "~/Library/Application Support/Puplet",
    "~/Library/Preferences/dev.dilee.puplet.plist",
  ]
end
EOF

step "Done"
cat <<EOF
  app     ${APP#$ROOT/}
  zip     ${ZIP#$ROOT/}
  sha256  $SHA
  cask    ${CASK#$ROOT/}

Publish:
  git tag -a v$VERSION -m "Puplet $VERSION" && git push origin v$VERSION
  gh release create v$VERSION "$ZIP" --repo $REPO --title "Puplet $VERSION" --generate-notes

Then copy the cask into your tap:
  cp ${CASK#$ROOT/} <path-to-$TAP>/Casks/puplet.rb

Users install with:
  brew install --cask dilee/tap/puplet
EOF

if [[ "$SKIP_NOTARIZE" -eq 1 ]]; then
  echo
  echo "REHEARSAL ONLY — not notarized. Do not publish this zip."
fi
