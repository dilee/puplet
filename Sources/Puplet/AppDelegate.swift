import AppKit

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) { fatalError("unused") }

    @objc private func fire() { handler() }
}

@MainActor
enum MenuBuilder {
    static func populate(_ menu: NSMenu, for controller: PetController) {
        menu.removeAllItems()

        let header = NSMenuItem(title: controller.petName, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(ClosureMenuItem(title: "Talk to \(controller.petName)…", keyEquivalent: "t") {
            controller.promptForChat()
        })
        menu.addItem(ClosureMenuItem(title: "Say Something") {
            controller.speak(.idleThought, force: true)
        })
        menu.addItem(ClosureMenuItem(title: "Come Here") {
            controller.fetchToCursor()
        })

        let pause = ClosureMenuItem(title: "Pause Wandering") {
            controller.isWanderingPaused.toggle()
        }
        pause.state = controller.isWanderingPaused ? .on : .off
        menu.addItem(pause)

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Rename…") {
            controller.promptForRename()
        })
        if controller.memoryCount > 0 {
            menu.addItem(ClosureMenuItem(title: "Forget Memories (\(controller.memoryCount))…") {
                controller.promptForgetMemories()
            })
        }

        menu.addItem(.separator())

        let brain = NSMenuItem(title: "Brain: \(controller.brainStatus)", action: nil, keyEquivalent: "")
        brain.isEnabled = false
        menu.addItem(brain)

        let chat = NSMenuItem(title: "Chat: \(controller.chatStatus)", action: nil, keyEquivalent: "")
        chat.isEnabled = false
        menu.addItem(chat)

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Quit Puplet", keyEquivalent: "q") {
            NSApp.terminate(nil)
        })
    }

    static func petMenu(for controller: PetController) -> NSMenu {
        let menu = NSMenu()
        populate(menu, for: controller)
        return menu
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static var shared: AppDelegate?

    private var statusItem: NSStatusItem?
    private var pet: PetController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = PetController(useOnDeviceModel: true)
        pet = controller
        controller.start()
        installStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pet?.stop()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Puplet")
        item.button?.toolTip = "Puplet"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let pet else { return }
        MenuBuilder.populate(menu, for: pet)
        statusItem?.button?.toolTip = pet.petName
    }
}
