import AppKit

final class WorkspaceContext {
    private(set) var frontmostApp: String = ""

    var onAppSwitch: ((String) -> Void)?

    private var observer: NSObjectProtocol?

    func start() {
        frontmostApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let self,
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                let name = app.localizedName,
                name != self.frontmostApp,
                name != "Puplet"
            else { return }
            self.frontmostApp = name
            self.onAppSwitch?(name)
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    enum DayPart: String {
        case earlyMorning, morning, afternoon, evening, night
    }

    var dayPart: DayPart {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<8: return .earlyMorning
        case 8..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<22: return .evening
        default: return .night
        }
    }
}
