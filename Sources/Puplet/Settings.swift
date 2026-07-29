import AppKit

@MainActor
final class PetSettings {
    static let shared = PetSettings()

    static let defaultName = "Pip"
    static let maxNameLength = 24

    private enum Key {
        static let name = "petName"
    }

    private let defaults = UserDefaults.standard

    var name: String {
        get { defaults.string(forKey: Key.name) ?? Self.defaultName }
        set { defaults.set(Self.sanitize(newValue), forKey: Key.name) }
    }

    static func sanitize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultName }
        return String(trimmed.prefix(maxNameLength))
    }
}

@MainActor
enum RenameDialog {
    static func run(currentName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Name your pet"
        alert.informativeText = "What should the pup be called?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = currentName
        field.placeholderString = PetSettings.defaultName
        alert.accessoryView = field

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let cleaned = PetSettings.sanitize(field.stringValue)
        return cleaned == currentName ? nil : cleaned
    }
}
