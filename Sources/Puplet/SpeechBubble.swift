import AppKit

final class BubbleView: NSView {
    var text: String = "" {
        didSet { needsDisplay = true }
    }

    static let maxWidth: CGFloat = 220
    static let padding = NSSize(width: 13, height: 9)
    static let tailHeight: CGFloat = 8

    static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
        .foregroundColor: NSColor(srgbRed: 0.16, green: 0.13, blue: 0.12, alpha: 1)
    ]

    static func size(for text: String) -> NSSize {
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: maxWidth - padding.width * 2, height: 400),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return NSSize(
            width: ceil(bounds.width) + padding.width * 2,
            height: ceil(bounds.height) + padding.height * 2 + tailHeight
        )
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let box = NSRect(
            x: 0,
            y: Self.tailHeight,
            width: bounds.width,
            height: bounds.height - Self.tailHeight
        )

        let path = CGMutablePath()
        path.addRoundedRect(in: box, cornerWidth: 11, cornerHeight: 11)
        let tailX = bounds.midX
        path.move(to: CGPoint(x: tailX - 7, y: box.minY + 1))
        path.addLine(to: CGPoint(x: tailX + 1, y: 0))
        path.addLine(to: CGPoint(x: tailX + 7, y: box.minY + 1))
        path.closeSubpath()

        ctx.addPath(path)
        ctx.setFillColor(NSColor(srgbRed: 1, green: 0.99, blue: 0.96, alpha: 0.97).cgColor)
        ctx.fillPath()

        ctx.addPath(path)
        ctx.setStrokeColor(NSColor(srgbRed: 0.20, green: 0.16, blue: 0.15, alpha: 0.85).cgColor)
        ctx.setLineWidth(1.6)
        ctx.strokePath()

        let textRect = NSRect(
            x: Self.padding.width,
            y: box.minY + Self.padding.height,
            width: box.width - Self.padding.width * 2,
            height: box.height - Self.padding.height * 2
        )
        (text as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: Self.attributes)
    }
}

final class BubbleController {
    private let panel: OverlayPanel
    private let view = BubbleView()
    private var hideWork: DispatchWorkItem?

    private(set) var isVisible = false

    init() {
        panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10))
        panel.contentView = view
        panel.alphaValue = 0
    }

    func show(_ text: String, above petFrame: NSRect, sticky: Bool = false) {
        hideWork?.cancel()
        hideWork = nil
        view.text = text
        let size = BubbleView.size(for: text)
        panel.setContentSize(size)
        isVisible = true
        reposition(above: petFrame)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }

        guard !sticky else { return }
        let words = text.split(separator: " ").count
        let lifetime = min(max(2.2 + Double(words) * 0.32, 2.5), 9.0)
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime, execute: work)
    }

    func update(_ text: String, above petFrame: NSRect) {
        hideWork?.cancel()
        hideWork = nil
        view.text = text
        panel.setContentSize(BubbleView.size(for: text))
        isVisible = true
        reposition(above: petFrame)
        panel.orderFrontRegardless()
        panel.alphaValue = 1
    }

    func reposition(above petFrame: NSRect) {
        guard isVisible else { return }
        let size = panel.frame.size
        var origin = NSPoint(x: petFrame.midX - size.width / 2, y: petFrame.maxY - 14)
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(petFrame) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
            origin.y = min(origin.y, visible.maxY - size.height - 4)
        }
        panel.setFrameOrigin(origin)
    }

    func hide() {
        hideWork?.cancel()
        guard isVisible else { return }
        isVisible = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        }
    }
}
