import AppKit

private final class ChatInputPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class InputBackdrop: NSView {
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let box = bounds.insetBy(dx: 1, dy: 1)
        let path = CGPath(roundedRect: box, cornerWidth: 11, cornerHeight: 11, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(NSColor(srgbRed: 1, green: 0.99, blue: 0.96, alpha: 0.97).cgColor)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(NSColor(srgbRed: 0.20, green: 0.16, blue: 0.15, alpha: 0.85).cgColor)
        ctx.setLineWidth(1.6)
        ctx.strokePath()
    }
}

@MainActor
final class ChatInputController: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    var onSubmit: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    private static let size = NSSize(width: 248, height: 34)
    private static let maxMessageLength = 500

    private let panel = ChatInputPanel(contentRect: NSRect(origin: .zero, size: ChatInputController.size))
    private let field = NSTextField()

    private(set) var isVisible = false

    override init() {
        super.init()
        let backdrop = InputBackdrop(frame: NSRect(origin: .zero, size: Self.size))
        field.frame = NSRect(x: 13, y: 8, width: Self.size.width - 26, height: 19)
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = BubbleView.attributes[.font] as? NSFont
        field.textColor = BubbleView.attributes[.foregroundColor] as? NSColor
        field.delegate = self
        backdrop.addSubview(field)
        panel.contentView = backdrop
        panel.delegate = self
    }

    func show(above petFrame: NSRect, petName: String) {
        field.placeholderString = "say something to \(petName)…"
        field.stringValue = ""
        isVisible = true
        reposition(above: petFrame)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    func reposition(above petFrame: NSRect) {
        guard isVisible else { return }
        var origin = NSPoint(x: petFrame.midX - Self.size.width / 2, y: petFrame.maxY - 6)
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(petFrame) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - Self.size.width - 4)
            origin.y = min(origin.y, visible.maxY - Self.size.height - 4)
        }
        panel.setFrameOrigin(origin)
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        panel.orderOut(nil)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return true }
            hide()
            onSubmit?(String(text.prefix(Self.maxMessageLength)))
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismiss()
            return true
        }
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        dismiss()
    }

    private func dismiss() {
        guard isVisible else { return }
        hide()
        onDismiss?()
    }
}
