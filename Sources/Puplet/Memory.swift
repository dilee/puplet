import Foundation

final class PetMemory: @unchecked Sendable {
    struct Fact: Codable {
        var text: String
        var created: Date
    }

    static let supportDirectory: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Puplet", isDirectory: true)
    }()

    private static let capacity = 60

    private let url: URL
    private let lock = NSLock()
    private var facts: [Fact]

    init(url: URL = PetMemory.supportDirectory.appendingPathComponent("memory.json")) {
        self.url = url
        Self.migrateLegacyStore(to: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: url),
           let decoded = try? decoder.decode([Fact].self, from: data) {
            facts = decoded
        } else {
            facts = []
        }
    }

    private static func migrateLegacyStore(to url: URL) {
        let legacy = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIPet/memory.json")
        guard FileManager.default.fileExists(atPath: legacy.path),
              !FileManager.default.fileExists(atPath: url.path)
        else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.moveItem(at: legacy, to: url)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return facts.count
    }

    func remember(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 200 else { return }
        lock.lock()
        defer { lock.unlock() }
        let lowered = cleaned.lowercased()
        guard !facts.contains(where: { $0.text.lowercased() == lowered }) else { return }
        facts.append(Fact(text: cleaned, created: Date()))
        if facts.count > Self.capacity {
            facts.removeFirst(facts.count - Self.capacity)
        }
        persist()
    }

    func forgetEverything() {
        lock.lock()
        defer { lock.unlock() }
        facts = []
        persist()
    }

    func promptFacts(limit: Int = 12) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return facts.suffix(limit).map(\.text)
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(facts).write(to: url, options: .atomic)
        } catch {
            NSLog("Puplet memory: failed to save: %@", String(describing: error))
        }
    }
}
