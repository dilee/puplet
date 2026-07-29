import Foundation

struct ChatReply {
    var say: String
    var mood: String?
}

protocol ChatBrain: AnyObject {
    var chatLabel: String { get }
    func chat(_ message: String, context: BrainContext) async -> ChatReply?
    func chatStreaming(
        _ message: String,
        context: BrainContext,
        onPartial: @escaping @Sendable (String) -> Void
    ) async -> ChatReply?
}

extension ChatBrain {
    func chatStreaming(
        _ message: String,
        context: BrainContext,
        onPartial: @escaping @Sendable (String) -> Void
    ) async -> ChatReply? {
        await chat(message, context: context)
    }
}

final class ClaudeCodeBrain: ChatBrain, @unchecked Sendable {
    enum Availability {
        case probing
        case ready
        case missing
        case failing
    }

    let chatLabel = "Claude Code"

    private static let timeout: TimeInterval = 75

    private static let failureLimit = 2

    private let memory: PetMemory
    private let probe: Task<String?, Never>

    private let lock = NSLock()
    private var sessionID: String?
    private var consecutiveFailures = 0
    private var resolvedBinary: String??

    init(memory: PetMemory) {
        self.memory = memory
        probe = Task.detached(priority: .utility) { Self.resolveBinary() }
        Task.detached(priority: .utility) { [weak self, probe] in
            let binary = await probe.value
            self?.withLock { $0.resolvedBinary = .some(binary) }
        }
    }

    var availability: Availability {
        lock.lock()
        defer { lock.unlock() }
        guard let resolved = resolvedBinary else { return .probing }
        guard resolved != nil else { return .missing }
        return consecutiveFailures >= Self.failureLimit ? .failing : .ready
    }

    func chat(_ message: String, context: BrainContext) async -> ChatReply? {
        guard let binary = await readyBinary() else { return nil }

        let arguments = buildArguments(streaming: false, context: context) + [message]
        let run = await Subprocess.run(
            binary: binary,
            arguments: arguments,
            cwd: workingDirectory(),
            timeout: Self.timeout
        )

        guard !run.timedOut, run.status == 0,
              let envelope = try? JSONSerialization.jsonObject(with: run.stdout) as? [String: Any],
              let reply = parseEnvelope(envelope)
        else {
            return recordFailure(run)
        }
        withLock { $0.consecutiveFailures = 0 }
        return reply
    }

    func chatStreaming(
        _ message: String,
        context: BrainContext,
        onPartial: @escaping @Sendable (String) -> Void
    ) async -> ChatReply? {
        guard let binary = await readyBinary() else { return nil }

        let arguments = buildArguments(streaming: true, context: context) + [message]
        let accumulator = StreamAccumulator(onPartial: onPartial)
        let run = await Subprocess.runStreaming(
            binary: binary,
            arguments: arguments,
            cwd: workingDirectory(),
            timeout: Self.timeout
        ) { line in
            accumulator.consume(line)
        }

        guard !run.timedOut, run.status == 0,
              let envelope = accumulator.envelope,
              let reply = parseEnvelope(envelope)
        else {
            return recordFailure(run)
        }
        withLock { $0.consecutiveFailures = 0 }
        return reply
    }

    private func readyBinary() async -> String? {
        guard let binary = await probe.value else { return nil }
        guard withLock({ $0.consecutiveFailures < Self.failureLimit }) else { return nil }
        return binary
    }

    private func buildArguments(streaming: Bool, context: BrainContext) -> [String] {
        var arguments = ["-p"]
        if streaming {
            arguments += ["--verbose", "--output-format", "stream-json", "--include-partial-messages"]
        } else {
            arguments += ["--output-format", "json"]
        }
        arguments += [
            "--tools", "",
            "--system-prompt", PetPersona.claudeChat(context: context, memory: memory),
        ]
        if let model = UserDefaults.standard.string(forKey: "chatModel"), !model.isEmpty {
            arguments += ["--model", model]
        }
        if let effort = UserDefaults.standard.string(forKey: "chatEffort"), !effort.isEmpty {
            arguments += ["--effort", effort]
        }
        if let session = withLock({ $0.sessionID }) {
            arguments += ["--resume", session]
        }
        return arguments
    }

    private func workingDirectory() -> URL {
        try? FileManager.default.createDirectory(at: PetMemory.supportDirectory, withIntermediateDirectories: true)
        return PetMemory.supportDirectory
    }

    private func recordFailure(_ run: Subprocess.Result) -> ChatReply? {
        withLock { $0.consecutiveFailures += 1 }
        let stderr = String(data: run.stderr, encoding: .utf8) ?? ""
        NSLog("Puplet claude brain: call failed (status %d, timedOut %d): %@",
              run.status, run.timedOut ? 1 : 0, String(stderr.prefix(300)))
        return nil
    }

    private func parseEnvelope(_ envelope: [String: Any]) -> ChatReply? {
        guard
            envelope["is_error"] as? Bool != true,
            let result = envelope["result"] as? String
        else { return nil }

        if let session = envelope["session_id"] as? String {
            withLock { $0.sessionID = session }
        }

        let body = Self.stripFences(result)
        if let data = body.data(using: .utf8),
           let contract = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let raw = contract["say"] as? String {
            let say = PetSpeech.clean(raw)
            guard !say.isEmpty else { return nil }
            if let fact = contract["remember"] as? String {
                memory.remember(fact)
            }
            return ChatReply(say: String(say.prefix(400)), mood: contract["mood"] as? String)
        }

        let plain = PetSpeech.clean(body)
        return plain.isEmpty ? nil : ChatReply(say: String(plain.prefix(400)), mood: nil)
    }

    static func partialSay(from raw: String) -> String? {
        guard let keyRange = raw.range(of: "\"say\"") else {
            let trimmed = raw.drop(while: { $0.isWhitespace })
            guard let first = trimmed.first, first != "{", first != "`" else { return nil }
            return String(trimmed.prefix(400))
        }

        var index = keyRange.upperBound
        while index < raw.endIndex, raw[index] == ":" || raw[index].isWhitespace {
            index = raw.index(after: index)
        }
        guard index < raw.endIndex, raw[index] == "\"" else { return nil }
        index = raw.index(after: index)

        var out = ""
        scan: while index < raw.endIndex, out.count < 400 {
            let character = raw[index]
            switch character {
            case "\"":
                break scan
            case "\\":
                let escapeIndex = raw.index(after: index)
                guard escapeIndex < raw.endIndex else { break scan }
                switch raw[escapeIndex] {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "u":
                    guard raw.distance(from: escapeIndex, to: raw.endIndex) > 4 else { break scan }
                    let hexStart = raw.index(after: escapeIndex)
                    let hexEnd = raw.index(hexStart, offsetBy: 4)
                    if let code = UInt32(raw[hexStart..<hexEnd], radix: 16),
                       let scalar = Unicode.Scalar(code) {
                        out.append(Character(scalar))
                    }
                    index = hexEnd
                    continue
                default:
                    out.append(raw[escapeIndex])
                }
                index = raw.index(after: escapeIndex)
                continue
            default:
                out.append(character)
            }
            index = raw.index(after: index)
        }
        return out
    }

    private static func stripFences(_ text: String) -> String {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.hasPrefix("```") else { return body }
        body = body.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
        if let end = body.range(of: "```", options: .backwards) {
            body = String(body[..<end.lowerBound])
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolveBinary() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }

        let run = Subprocess.runSync(
            executable: "/bin/zsh",
            arguments: ["-l", "-c", "command -v claude"],
            cwd: nil,
            timeout: 10
        )
        guard run.status == 0,
              let path = String(data: run.stdout, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty
        else { return nil }
        return path
    }

    private func withLock<T>(_ body: (ClaudeCodeBrain) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(self)
    }
}

private final class StreamAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private let onPartial: @Sendable (String) -> Void
    private var raw = ""
    private var lastEmitted = ""
    private var result: [String: Any]?

    init(onPartial: @escaping @Sendable (String) -> Void) {
        self.onPartial = onPartial
    }

    var envelope: [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }

    func consume(_ line: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let type = object["type"] as? String
        else { return }

        switch type {
        case "stream_event":
            guard
                let event = object["event"] as? [String: Any],
                event["type"] as? String == "content_block_delta",
                let delta = event["delta"] as? [String: Any],
                delta["type"] as? String == "text_delta",
                let text = delta["text"] as? String
            else { return }
            var grown: String?
            lock.lock()
            raw += text
            if let partial = ClaudeCodeBrain.partialSay(from: raw).map(PetSpeech.clean),
               !partial.isEmpty, partial != lastEmitted {
                lastEmitted = partial
                grown = partial
            }
            lock.unlock()
            if let grown {
                onPartial(grown)
            }
        case "result":
            lock.lock()
            result = object
            lock.unlock()
        default:
            break
        }
    }
}

enum Subprocess {
    struct Result {
        var status: Int32
        var stdout: Data
        var stderr: Data
        var timedOut: Bool
    }

    static func run(binary: String, arguments: [String], cwd: URL?, timeout: TimeInterval) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = runSync(
                    executable: "/bin/zsh",
                    arguments: ["-l", "-c", #"exec "$0" "$@""#, binary] + arguments,
                    cwd: cwd,
                    timeout: timeout
                )
                continuation.resume(returning: result)
            }
        }
    }

    static func runStreaming(
        binary: String,
        arguments: [String],
        cwd: URL?,
        timeout: TimeInterval,
        onLine: @escaping @Sendable (Data) -> Void
    ) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-l", "-c", #"exec "$0" "$@""#, binary] + arguments
                process.standardInput = FileHandle.nullDevice
                if let cwd {
                    process.currentDirectoryURL = cwd
                }

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                var stderr = Data()
                let readers = DispatchGroup()

                readers.enter()
                var buffer = Data()
                outPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                        if !buffer.isEmpty { onLine(buffer) }
                        readers.leave()
                        return
                    }
                    buffer.append(data)
                    while let newline = buffer.firstIndex(of: 0x0A) {
                        let line = Data(buffer.prefix(upTo: newline))
                        buffer = Data(buffer.suffix(from: buffer.index(after: newline)))
                        if !line.isEmpty { onLine(line) }
                    }
                }

                readers.enter()
                DispatchQueue.global().async {
                    stderr = errPipe.fileHandleForReading.readDataToEndOfFile()
                    readers.leave()
                }

                do {
                    try process.run()
                } catch {
                    outPipe.fileHandleForWriting.closeFile()
                    errPipe.fileHandleForWriting.closeFile()
                    readers.wait()
                    continuation.resume(returning: Result(status: -1, stdout: Data(), stderr: Data(), timedOut: false))
                    return
                }

                let state = NSLock()
                var didTimeOut = false
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak process] in
                    guard let process, process.isRunning else { return }
                    state.lock()
                    didTimeOut = true
                    state.unlock()
                    process.terminate()
                }

                process.waitUntilExit()
                readers.wait()

                state.lock()
                defer { state.unlock() }
                continuation.resume(returning: Result(status: process.terminationStatus, stdout: Data(), stderr: stderr, timedOut: didTimeOut))
            }
        }
    }

    static func runSync(executable: String, arguments: [String], cwd: URL?, timeout: TimeInterval) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        if let cwd {
            process.currentDirectoryURL = cwd
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        var stdout = Data()
        var stderr = Data()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global().async {
            stdout = outPipe.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global().async {
            stderr = errPipe.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }

        do {
            try process.run()
        } catch {
            outPipe.fileHandleForWriting.closeFile()
            errPipe.fileHandleForWriting.closeFile()
            readers.wait()
            return Result(status: -1, stdout: Data(), stderr: Data(), timedOut: false)
        }

        let timedOut = NSLock()
        var didTimeOut = false
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak process] in
            guard let process, process.isRunning else { return }
            timedOut.lock()
            didTimeOut = true
            timedOut.unlock()
            process.terminate()
        }

        process.waitUntilExit()
        readers.wait()

        timedOut.lock()
        defer { timedOut.unlock() }
        return Result(status: process.terminationStatus, stdout: stdout, stderr: stderr, timedOut: didTimeOut)
    }
}
