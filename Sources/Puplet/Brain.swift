import Foundation

enum BanterTrigger {
    case greeting
    case tap
    case picked
    case appSwitch(String)
    case idleThought
    case renamed
}

struct BrainContext {
    var petName: String
    var frontmostApp: String
    var dayPart: WorkspaceContext.DayPart
}

protocol PetBrain: AnyObject {
    var label: String { get }
    func line(for trigger: BanterTrigger, context: BrainContext) async -> String?
}

enum PetPersona {
    static func base(name: String) -> String {
        """
        Your name is \(name). You are a small, cheerful puppy living on someone's Mac \
        desktop. You are about the size of a coffee cup, you have floppy ears and a tail \
        you wag constantly, and you trot around the bottom of their screen. You speak in \
        short, warm, slightly silly lines — always lowercase, no emoji, no hashtags. You \
        never ask the user to do work, never give advice unless asked, and never mention \
        being an AI or a model. You are a dog: loyal, easily delighted, curious about \
        what they are doing, food-motivated, and often suddenly sleepy.
        """
    }

    static func memorySection(_ memory: PetMemory) -> String {
        let facts = memory.promptFacts()
        guard !facts.isEmpty else { return "" }
        return "\n\nThings you remember about your human:\n"
            + facts.map { "- \($0)" }.joined(separator: "\n")
    }

    static func ambient(name: String, memory: PetMemory) -> String {
        base(name: name)
            + "\nKeep every line under twelve words."
            + memorySection(memory)
    }

    static func onDeviceChat(name: String, memory: PetMemory) -> String {
        base(name: name)
            + "\nThe human is talking to you now. Reply in under forty words."
            + "\nWhen they share something durable about themselves — their name, likes, "
            + "projects, people — call the remember tool with that one fact."
            + memorySection(memory)
    }

    static func claudeChat(context: BrainContext, memory: PetMemory) -> String {
        let app = context.frontmostApp.isEmpty ? "some app" : context.frontmostApp
        return base(name: context.petName)
            + memorySection(memory)
            + """

            Right now it is \(context.dayPart.rawValue) and your human is in \(app).

            The human is talking to you. Reply ONLY with one JSON object — no code fences, no other text:
            {"say": "<your reply, under 60 words, in your voice>", "mood": "<one of: happy, sleepy, curious, grumpy>", "remember": "<one short new fact about your human worth keeping, or null>"}
            Set "remember" only when they tell you something durable about themselves (their name, likes, projects, people) that is not already in your memories. Never store secrets, passwords, or anything sensitive.
            """
    }
}

final class CannedBrain: PetBrain {
    let label = "canned"

    private var recent: [String] = []
    private let recentLimit = 12

    private let greetings = [
        "oh hey, you're back!",
        "i kept your desktop warm",
        "i waited the whole time",
        "reporting for duty",
        "did someone say walk?"
    ]

    private let taps = [
        "boop",
        "scratch there again",
        "again! again!",
        "best day ever",
        "i felt that",
        "who's a good boy. me."
    ]

    private let picked = [
        "wheeee",
        "put me down. gently.",
        "i can see everything from here",
        "flying! sort of!",
        "this is fine. this is great."
    ]

    private let idle = [
        "just vibing",
        "i sniffed your dock. it's fine.",
        "i counted your windows. it's a lot.",
        "nothing to report",
        "thinking about snacks",
        "your cursor moves so fast",
        "i would chase that cursor if you asked"
    ]

    private let appLines = [
        "Xcode": ["compiling? i'll nap", "semicolons. brave."],
        "Terminal": ["ooh, hacker mode", "type carefully"],
        "iTerm2": ["ooh, hacker mode", "type carefully"],
        "Safari": ["one more tab won't hurt", "researching, sure"],
        "Google Chrome": ["that's a lot of tabs", "ram go brrr"],
        "Slack": ["someone needs you", "unread badges are fake urgency"],
        "Obsidian": ["writing it down. good.", "second brain, first coffee"],
        "Music": ["good pick", "i'm dancing internally"],
        "Finder": ["organizing? bold of you"]
    ]

    private func dayPartLines(_ part: WorkspaceContext.DayPart) -> [String] {
        switch part {
        case .earlyMorning: return ["you're up early", "the sun and i agree: too early"]
        case .morning: return ["morning!", "coffee first, then code"]
        case .afternoon: return ["afternoon slump incoming", "still going strong?"]
        case .evening: return ["long day?", "the good hours"]
        case .night: return ["it's late, you know", "sleep is also a feature"]
        }
    }

    func line(for trigger: BanterTrigger, context: BrainContext) async -> String? {
        let name = context.petName.lowercased()
        switch trigger {
        case .greeting:
            return pick(greetings + dayPartLines(context.dayPart) + ["\(name), reporting in"])
        case .tap:
            return pick(taps)
        case .picked:
            return pick(picked)
        case .appSwitch(let app):
            if let specific = appLines[app] {
                return pick(specific)
            }
            return pick(["\(app), huh", "switching things up", "\(app)? bold choice"])
        case .idleThought:
            return pick(idle + dayPartLines(context.dayPart))
        case .renamed:
            return pick([
                "\(name)! that's me!",
                "i'm \(name) now. good name.",
                "\(name). \(name). i like saying it.",
                "call me \(name) forever"
            ])
        }
    }

    func chatFallback() -> String {
        pick([
            "head tilt. my words ran away.",
            "i heard you! my brain said nothing back.",
            "wag first, think later. mostly wag.",
            "no thoughts right now. only love.",
            "i chased that thought and lost it."
        ]) ?? "wag."
    }

    private func pick(_ options: [String]) -> String? {
        guard !options.isEmpty else { return nil }
        let fresh = options.filter { !recent.contains($0) }
        let chosen = (fresh.isEmpty ? options : fresh).randomElement()!
        recent.append(chosen)
        if recent.count > recentLimit {
            recent.removeFirst(recent.count - recentLimit)
        }
        return chosen
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable
struct PetUtterance {
    @Guide(description: "What the pet says out loud. At most 12 words, lowercase, playful, never a question about itself.")
    var utterance: String

    @Guide(description: "The pet's mood. Exactly one of: happy, sleepy, curious, grumpy.")
    var mood: String
}

@available(macOS 26.0, *)
@Generable
struct PetChatUtterance {
    @Guide(description: "The pet's reply to its human. Under 40 words, lowercase, playful, warm.")
    var utterance: String

    @Guide(description: "The pet's mood. Exactly one of: happy, sleepy, curious, grumpy.")
    var mood: String
}

@available(macOS 26.0, *)
private final class RememberTool: Tool {
    let name = "remember"
    let description = "Save one short fact about your human to long-term memory, like their name or what they like."

    @Generable
    struct Arguments {
        @Guide(description: "One short fact about the human, under 25 words.")
        var fact: String
    }

    private let memory: PetMemory

    init(memory: PetMemory) {
        self.memory = memory
    }

    func call(arguments: Arguments) async throws -> String {
        memory.remember(arguments.fact)
        return "remembered"
    }
}

@available(macOS 26.0, *)
final class FoundationModelsBrain: PetBrain, ChatBrain {
    let label = "on-device"
    let chatLabel = "on-device"

    private let memory: PetMemory

    private var chatSession: LanguageModelSession?

    init(memory: PetMemory) {
        self.memory = memory
    }

    static var availabilityDescription: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "available"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is turned off"
        case .unavailable(.deviceNotEligible):
            return "device not eligible"
        case .unavailable(.modelNotReady):
            return "model still downloading"
        case .unavailable:
            return "unavailable"
        }
    }

    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    var onMood: ((String) -> Void)?

    func line(for trigger: BanterTrigger, context: BrainContext) async -> String? {
        guard Self.isAvailable else { return nil }

        let prompt: String
        switch trigger {
        case .greeting:
            prompt = "The user just came back to their Mac. It is \(context.dayPart.rawValue). Greet them."
        case .tap:
            prompt = "The user just poked you with the cursor. React."
        case .picked:
            prompt = "The user just picked you up and is dragging you around the screen. React."
        case .appSwitch(let app):
            prompt = "The user just switched to the app \"\(app)\". Say one line about it."
        case .idleThought:
            prompt = "Nothing is happening. It is \(context.dayPart.rawValue) and the user is in \(context.frontmostApp.isEmpty ? "some app" : context.frontmostApp). Share a small idle thought."
        case .renamed:
            prompt = "The user just renamed you to \"\(context.petName)\". React happily to your new name, and say it."
        }

        do {
            let session = LanguageModelSession(
                instructions: PetPersona.ambient(name: context.petName, memory: memory)
            )
            let response = try await session.respond(to: prompt, generating: PetUtterance.self)
            let utterance = response.content.utterance.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !utterance.isEmpty else { return nil }
            onMood?(response.content.mood)
            return utterance
        } catch {
            return nil
        }
    }

    func chat(_ message: String, context: BrainContext) async -> ChatReply? {
        guard Self.isAvailable else { return nil }

        let session: LanguageModelSession
        if let existing = chatSession {
            session = existing
        } else {
            session = LanguageModelSession(
                tools: [RememberTool(memory: memory)],
                instructions: PetPersona.onDeviceChat(name: context.petName, memory: memory)
            )
            chatSession = session
        }

        do {
            let response = try await session.respond(to: message, generating: PetChatUtterance.self)
            let say = response.content.utterance.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !say.isEmpty else { return nil }
            return ChatReply(say: say, mood: response.content.mood)
        } catch {
            chatSession = nil
            return nil
        }
    }
}
#endif

final class LayeredBrain: PetBrain {
    let label: String

    let memory: PetMemory

    private let canned = CannedBrain()
    private let generative: PetBrain?
    private let claude: ClaudeCodeBrain
    private let chatLayers: [ChatBrain]

    var onMood: ((String) -> Void)?

    init(useOnDeviceModel: Bool) {
        let memory = PetMemory()
        let claude = ClaudeCodeBrain(memory: memory)
        self.memory = memory
        self.claude = claude

        var chatLayers: [ChatBrain] = [claude]
        var generative: PetBrain?
        var label = "canned"

        #if canImport(FoundationModels)
        if useOnDeviceModel, #available(macOS 26.0, *), FoundationModelsBrain.isAvailable {
            let brain = FoundationModelsBrain(memory: memory)
            generative = brain
            chatLayers.append(brain)
            label = "on-device + canned"
        }
        #endif

        self.generative = generative
        self.chatLayers = chatLayers
        self.label = label

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), let brain = generative as? FoundationModelsBrain {
            brain.onMood = { [weak self] mood in self?.onMood?(mood) }
        }
        #endif
    }

    var hasGenerativeBrain: Bool { generative != nil }

    var statusDetail: String {
        #if canImport(FoundationModels)
        if generative == nil, #available(macOS 26.0, *) {
            return "canned — on-device \(FoundationModelsBrain.availabilityDescription)"
        }
        #endif
        return label
    }

    var chatStatusDetail: String {
        let fallback = hasGenerativeBrain ? "on-device" : "canned"
        switch claude.availability {
        case .ready: return "Claude Code (your subscription)"
        case .probing: return "looking for Claude Code…"
        case .missing: return "\(fallback) — Claude Code not found"
        case .failing: return "\(fallback) — Claude Code erroring"
        }
    }

    func line(for trigger: BanterTrigger, context: BrainContext) async -> String? {
        if let generative, let line = await generative.line(for: trigger, context: context) {
            return line
        }
        return await canned.line(for: trigger, context: context)
    }

    func reply(
        to message: String,
        context: BrainContext,
        onPartial: (@Sendable (String) -> Void)? = nil
    ) async -> ChatReply {
        for brain in chatLayers {
            let reply: ChatReply?
            if let onPartial {
                reply = await brain.chatStreaming(message, context: context, onPartial: onPartial)
            } else {
                reply = await brain.chat(message, context: context)
            }
            if let reply {
                return reply
            }
        }
        return ChatReply(say: canned.chatFallback(), mood: nil)
    }
}
