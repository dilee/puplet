import AppKit
import SpriteKit

final class PetSurfaceView: SKView {
    weak var controller: PetController?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { controller?.beginDrag() }
    override func mouseDragged(with event: NSEvent) { controller?.updateDrag() }
    override func mouseUp(with event: NSEvent) { controller?.endDrag(clickCount: event.clickCount) }
    override func rightMouseDown(with event: NSEvent) { controller?.showContextMenu(with: event) }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

@MainActor
final class PetController {
    private let panel: PetPanel
    private let surface: PetSurfaceView
    private let scene: PetScene
    private let bubble = BubbleController()
    private let chatInput = ChatInputController()
    private let machine = BehaviorMachine()
    private let workspace = WorkspaceContext()
    private let brain: LayeredBrain

    var petName: String { PetSettings.shared.name }

    private var origin: CGPoint = .zero
    private var verticalVelocity: CGFloat = 0
    private var lastFacing: CGFloat = 1

    private var isDragging = false
    private var dragOffset = CGSize.zero
    private var dragStart = CGPoint.zero
    private var mouseInside = false
    private var homeScreenID: CGDirectDisplayID?

    private var nextIdleThought: TimeInterval = .random(in: 40...90)
    private var lastSpoke = Date.distantPast
    private var isGenerating = false
    private var isChatting = false
    private var holdStill = false

    var isWanderingPaused = false

    private static let walkSpeed: CGFloat = 46
    private static let gravity: CGFloat = -1600
    private static let canvas = CreatureRenderer.canvas

    private static let interactiveCore = CGRect(x: 19, y: 5, width: 58, height: 60)

    var brainStatus: String { brain.statusDetail }
    var chatStatus: String { brain.chatStatusDetail }
    var memoryCount: Int { brain.memory.count }

    init(useOnDeviceModel: Bool) {
        brain = LayeredBrain(useOnDeviceModel: useOnDeviceModel)

        let rect = NSRect(origin: .zero, size: Self.canvas)
        panel = PetPanel(contentRect: rect)
        scene = PetScene(size: Self.canvas)
        surface = PetSurfaceView(frame: rect)
        surface.allowsTransparency = true
        surface.preferredFramesPerSecond = 60
        surface.presentScene(scene)
        panel.contentView = surface
        surface.controller = self

        machine.onEnter = { [weak self] state in
            self?.scene.play(state)
        }
        brain.onMood = { [weak self] mood in
            self?.apply(mood: mood)
        }
        scene.onFrame = { [weak self] dt in
            self?.step(dt)
        }

        workspace.onAppSwitch = { [weak self] app in
            guard let self, Double.random(in: 0...1) < 0.4 else { return }
            self.speak(.appSwitch(app))
        }

        chatInput.onSubmit = { [weak self] message in
            self?.chat(message)
        }
        chatInput.onDismiss = { [weak self] in
            guard let self, !self.isChatting else { return }
            self.holdStill = false
        }
    }

    func start() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        homeScreenID = screen.displayID
        origin = CGPoint(
            x: screen.visibleFrame.midX - Self.canvas.width / 2,
            y: screen.visibleFrame.minY
        )
        panel.setFrameOrigin(origin)
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        workspace.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.speak(.greeting)
        }
    }

    func stop() {
        workspace.stop()
        bubble.hide()
        chatInput.hide()
        panel.orderOut(nil)
    }

    private func step(_ dt: TimeInterval) {
        machine.step(dt)
        updateMouseGate()

        let screen = currentScreen
        let ground = screen.visibleFrame.minY

        if isDragging {
            let mouse = NSEvent.mouseLocation
            origin = CGPoint(x: mouse.x - dragOffset.width, y: mouse.y - dragOffset.height)
        } else if origin.y > ground + 0.5 || verticalVelocity != 0 {
            verticalVelocity += Self.gravity * CGFloat(dt)
            origin.y += verticalVelocity * CGFloat(dt)
            if origin.y <= ground {
                origin.y = ground
                if abs(verticalVelocity) > 280 {
                    verticalVelocity = -verticalVelocity * 0.3
                } else {
                    verticalVelocity = 0
                    machine.force(.excited)
                }
            }
        } else if machine.state == .walk && !isWanderingPaused && !holdStill {
            origin.x += machine.facing * Self.walkSpeed * CGFloat(dt)
        }

        clampToScreen(screen)

        if machine.facing != lastFacing {
            lastFacing = machine.facing
            scene.setFacing(machine.facing)
        }

        if panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
            bubble.reposition(above: panel.frame)
            chatInput.reposition(above: panel.frame)
        }

        nextIdleThought -= dt
        if nextIdleThought <= 0 {
            nextIdleThought = .random(in: 50...120)
            if machine.state != .sleep {
                speak(.idleThought)
            }
        }
    }

    private func clampToScreen(_ screen: NSScreen) {
        let visible = screen.visibleFrame
        let minX = visible.minX
        let maxX = visible.maxX - Self.canvas.width

        if origin.x < minX {
            origin.x = minX
            if machine.facing < 0 { machine.turnAround() }
        } else if origin.x > maxX {
            origin.x = maxX
            if machine.facing > 0 { machine.turnAround() }
        }

        origin.y = min(max(origin.y, visible.minY), visible.maxY - Self.canvas.height)
    }

    private var currentScreen: NSScreen {
        if let id = homeScreenID, let screen = NSScreen.screens.first(where: { $0.displayID == id }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    private func updateMouseGate() {
        guard !isDragging else { return }
        let mouse = NSEvent.mouseLocation
        let local = CGPoint(x: mouse.x - origin.x, y: mouse.y - origin.y)
        let inside = Self.interactiveCore.contains(local)
        guard inside != mouseInside else { return }
        mouseInside = inside
        panel.ignoresMouseEvents = !inside
    }

    func beginDrag() {
        let mouse = NSEvent.mouseLocation
        dragStart = mouse
        dragOffset = CGSize(width: mouse.x - origin.x, height: mouse.y - origin.y)
        isDragging = true
        verticalVelocity = 0
        machine.force(.excited)
    }

    func updateDrag() {
        guard isDragging else { return }
        if hypot(NSEvent.mouseLocation.x - dragStart.x, NSEvent.mouseLocation.y - dragStart.y) > 24,
           !bubble.isVisible,
           canSpeakSpontaneously {
            speak(.picked)
        }
    }

    func endDrag(clickCount: Int = 1) {
        guard isDragging else { return }
        isDragging = false

        let center = CGPoint(x: origin.x + Self.canvas.width / 2, y: origin.y + Self.canvas.height / 2)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            homeScreenID = screen.displayID
        }

        let travelled = hypot(NSEvent.mouseLocation.x - dragStart.x, NSEvent.mouseLocation.y - dragStart.y)
        if travelled < 4 {
            if clickCount >= 2 {
                bubble.hide()
                promptForChat()
            } else {
                tap()
            }
        }
    }

    private func tap() {
        machine.force(.excited)
        speak(.tap, force: true)
    }

    func promptForRename() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let newName = RenameDialog.run(currentName: self.petName) else { return }
            PetSettings.shared.name = newName
            self.machine.force(.excited)
            self.speak(.renamed, force: true)
        }
    }

    func promptForChat() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isChatting else { return }
            self.holdStill = true
            self.machine.force(.sit)
            if self.bubble.isVisible {
                self.bubble.hide()
            }
            self.chatInput.show(above: self.panel.frame, petName: self.petName)
        }
    }

    private func chat(_ message: String) {
        guard !isChatting else { return }
        isChatting = true
        holdStill = true
        machine.force(.sit)
        bubble.show("…", above: panel.frame, sticky: true)

        let context = BrainContext(
            petName: petName,
            frontmostApp: workspace.frontmostApp,
            dayPart: workspace.dayPart
        )

        Task { [weak self] in
            guard let self else { return }
            let reply = await self.brain.reply(to: message, context: context) { [weak self] partial in
                DispatchQueue.main.async {
                    guard let self, self.isChatting else { return }
                    self.bubble.update(partial, above: self.panel.frame)
                }
            }
            self.isChatting = false
            self.holdStill = false
            self.lastSpoke = Date()
            if let mood = reply.mood {
                self.apply(mood: mood)
            } else if self.machine.state == .sit {
                self.machine.force(.idle)
            }
            self.bubble.show(reply.say, above: self.panel.frame)
        }
    }

    func promptForgetMemories() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let alert = NSAlert()
            alert.messageText = "Forget everything?"
            alert.informativeText = "\(self.petName) will forget all \(self.memoryCount) remembered facts. This can't be undone."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Forget")
            alert.addButton(withTitle: "Keep")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            self.brain.memory.forgetEverything()
            self.machine.force(.excited)
            self.bubble.show("who am i? who are you? exciting!", above: self.panel.frame)
        }
    }

    func fetchToCursor() {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            homeScreenID = screen.displayID
        }
        origin = CGPoint(x: mouse.x - Self.canvas.width / 2, y: mouse.y)
        verticalVelocity = 0
        machine.force(.excited)
    }

    func showContextMenu(with event: NSEvent) {
        let menu = MenuBuilder.petMenu(for: self)
        menu.popUp(positioning: nil, at: NSPoint(x: event.locationInWindow.x, y: event.locationInWindow.y), in: surface)
    }

    private var canSpeakSpontaneously: Bool {
        Date().timeIntervalSince(lastSpoke) > 20
    }

    func speak(_ trigger: BanterTrigger, force: Bool = false) {
        guard !isGenerating else { return }
        guard !isChatting, !chatInput.isVisible else { return }
        guard force || canSpeakSpontaneously else { return }
        isGenerating = true

        let context = BrainContext(
            petName: petName,
            frontmostApp: workspace.frontmostApp,
            dayPart: workspace.dayPart
        )

        Task { [weak self] in
            guard let self else { return }
            let line = await brain.line(for: trigger, context: context)
            self.isGenerating = false
            guard let line else { return }
            guard !self.isChatting, !self.chatInput.isVisible else { return }
            self.lastSpoke = Date()
            if self.machine.state == .sleep {
                self.machine.force(.idle)
            }
            self.bubble.show(line, above: self.panel.frame)
        }
    }

    private func apply(mood: String) {
        guard !isDragging else { return }
        switch mood.lowercased() {
        case "happy": machine.force(.excited)
        case "sleepy": machine.force(.sit)
        case "grumpy": machine.force(.sit)
        default: break
        }
    }
}
