import AppKit

struct CreatureStyle {
    var body = NSColor(srgbRed: 0.96, green: 0.79, blue: 0.55, alpha: 1)
    var muzzle = NSColor(srgbRed: 1.00, green: 0.97, blue: 0.91, alpha: 1)
    var ear = NSColor(srgbRed: 0.78, green: 0.55, blue: 0.34, alpha: 1)
    var ink = NSColor(srgbRed: 0.24, green: 0.16, blue: 0.12, alpha: 1)
    var blush = NSColor(srgbRed: 0.95, green: 0.58, blue: 0.56, alpha: 1)
    var tongue = NSColor(srgbRed: 0.94, green: 0.49, blue: 0.54, alpha: 1)

    static let `default` = CreatureStyle()
}

enum EyeShape {
    case open
    case closed
    case happy
}

struct Pose {
    var squash: CGFloat = 1.0
    var legPhase: CGFloat? = nil
    var eyes: EyeShape = .open
    var tailWag: CGFloat = 0
    var earFlop: CGFloat = 0
    var tongue = false
    var sleepZ: CGFloat? = nil
    var tucked = false
    var lift: CGFloat = 0
}

enum CreatureRenderer {
    static let canvas = CGSize(width: 96, height: 96)
    static let groundInset: CGFloat = 12

    private static let outline: CGFloat = 2.6

    static func image(for pose: Pose, style: CreatureStyle = .default) -> NSImage {
        render(size: canvas, scale: 2) { ctx in
            draw(pose: pose, style: style, in: ctx)
        }
    }

    private static func draw(pose: Pose, style: CreatureStyle, in ctx: CGContext) {
        let cx = canvas.width / 2
        let squash = pose.squash
        let ground = groundInset + pose.lift

        let h = 43 * squash * (pose.tucked ? 0.97 : 1.0)
        let w = pose.tucked ? 50 : 52 * (1 + (1 - squash) * 0.55)

        let bob = pose.legPhase.map { abs(sin($0 * 2 * .pi)) * 2 } ?? 0
        let bottom = pose.tucked ? ground : ground + 6 + bob
        let body = CGRect(x: cx - w / 2, y: bottom, width: w, height: h)

        ctx.setLineWidth(outline)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        drawTail(in: ctx, body: body, wag: pose.tailWag, style: style)
        if !pose.tucked {
            drawLegs(in: ctx, cx: cx, ground: ground, phase: pose.legPhase, style: style)
        }
        drawBody(in: ctx, body: body, style: style)
        if pose.tucked && pose.sleepZ == nil {
            drawSitPaws(in: ctx, cx: cx, ground: ground, style: style)
        }
        drawFace(in: ctx, body: body, pose: pose, style: style)
        drawEars(in: ctx, body: body, flop: pose.earFlop, droop: pose.sleepZ != nil ? 1 : 0, style: style)
        if let z = pose.sleepZ {
            drawSleepZ(in: ctx, anchor: CGPoint(x: body.maxX - 2, y: body.maxY + 4), progress: z, style: style)
        }
    }

    private static func blobPath(in rect: CGRect) -> CGPath {
        let cx = rect.midX
        let w = rect.width
        let h = rect.height
        let sideY = rect.minY + h * 0.45

        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: sideY),
            control1: CGPoint(x: cx + w * 0.30, y: rect.maxY),
            control2: CGPoint(x: rect.maxX, y: sideY + h * 0.32)
        )
        path.addCurve(
            to: CGPoint(x: cx, y: rect.minY),
            control1: CGPoint(x: rect.maxX, y: sideY - h * 0.26),
            control2: CGPoint(x: cx + w * 0.33, y: rect.minY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: sideY),
            control1: CGPoint(x: cx - w * 0.33, y: rect.minY),
            control2: CGPoint(x: rect.minX, y: sideY - h * 0.26)
        )
        path.addCurve(
            to: CGPoint(x: cx, y: rect.maxY),
            control1: CGPoint(x: rect.minX, y: sideY + h * 0.32),
            control2: CGPoint(x: cx - w * 0.30, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }

    private static func drawBody(in ctx: CGContext, body: CGRect, style: CreatureStyle) {
        let path = blobPath(in: body)
        ctx.addPath(path)
        ctx.setFillColor(style.body.cgColor)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(style.ink.cgColor)
        ctx.strokePath()

        let shine = CGRect(
            x: body.midX - body.width * 0.26,
            y: body.maxY - body.height * 0.24,
            width: body.width * 0.30,
            height: body.height * 0.14
        )
        ctx.saveGState()
        ctx.addPath(blobPath(in: body))
        ctx.clip()
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.22).cgColor)
        ctx.addEllipse(in: shine)
        ctx.fillPath()
        ctx.restoreGState()
    }

    private static func earPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addCurve(
            to: CGPoint(x: 13, y: -3),
            control1: CGPoint(x: 5.5, y: 4.5),
            control2: CGPoint(x: 10.5, y: 1.2)
        )
        path.addCurve(
            to: CGPoint(x: 11.5, y: -21),
            control1: CGPoint(x: 19.5, y: -9),
            control2: CGPoint(x: 16.5, y: -16.5)
        )
        path.addQuadCurve(
            to: CGPoint(x: 8, y: -19),
            control: CGPoint(x: 8.6, y: -22.6)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: 0),
            control1: CGPoint(x: 8.6, y: -11),
            control2: CGPoint(x: 4.2, y: -4)
        )
        path.closeSubpath()
        return path
    }

    private static func drawEars(in ctx: CGContext, body: CGRect, flop: CGFloat, droop: CGFloat, style: CreatureStyle) {
        let shape = earPath()
        for sign in [CGFloat(-1), 1] {
            ctx.saveGState()
            ctx.translateBy(x: body.midX + sign * body.width * 0.17, y: body.maxY - 2.5 - droop * 2)
            ctx.scaleBy(x: sign, y: 1)
            ctx.rotate(by: flop * 0.30 - droop * 0.22)
            ctx.addPath(shape)
            ctx.setFillColor(style.ear.cgColor)
            ctx.fillPath()
            ctx.addPath(shape)
            ctx.setStrokeColor(style.ink.cgColor)
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    private static func drawLegs(in ctx: CGContext, cx: CGFloat, ground: CGFloat, phase: CGFloat?, style: CreatureStyle) {
        let swing = phase.map { sin($0 * 2 * .pi) } ?? 0
        for sign in [CGFloat(-1), 1] {
            let step = max(0, sign * swing) * 3.5
            let paw = CGRect(x: cx + sign * 10 - 7.5, y: ground + step, width: 15, height: 11)
            let path = CGPath(roundedRect: paw, cornerWidth: 5.5, cornerHeight: 5.5, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(style.body.cgColor)
            ctx.fillPath()
            ctx.addPath(path)
            ctx.setStrokeColor(style.ink.cgColor)
            ctx.strokePath()
        }
    }

    private static func drawSitPaws(in ctx: CGContext, cx: CGFloat, ground: CGFloat, style: CreatureStyle) {
        for sign in [CGFloat(-1), 1] {
            let paw = CGRect(x: cx + sign * 10 - 6.5, y: ground, width: 13, height: 9)
            let path = CGPath(roundedRect: paw, cornerWidth: 4.5, cornerHeight: 4.5, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(style.body.cgColor)
            ctx.fillPath()
            ctx.addPath(path)
            ctx.setStrokeColor(style.ink.cgColor)
            ctx.strokePath()
        }
    }

    private static func drawTail(in ctx: CGContext, body: CGRect, wag: CGFloat, style: CreatureStyle) {
        let h = body.height
        let baseX = body.maxX - 8
        let rootLow = CGPoint(x: baseX, y: body.minY + h * 0.12)
        let rootHigh = CGPoint(x: baseX, y: body.minY + h * 0.42)

        let tipX = body.maxX + 6 + wag * 4.5
        let tipY = body.minY + h * 0.80
        let outerTip = CGPoint(x: tipX + 2.6, y: tipY - 1.9)
        let innerTip = CGPoint(x: tipX - 2.4, y: tipY - 2.8)

        let path = CGMutablePath()
        path.move(to: rootLow)
        path.addQuadCurve(
            to: outerTip,
            control: CGPoint(x: body.maxX + 12.5, y: body.minY + h * 0.32)
        )
        path.addQuadCurve(
            to: innerTip,
            control: CGPoint(x: tipX + 0.3, y: tipY + 4.1)
        )
        path.addQuadCurve(
            to: rootHigh,
            control: CGPoint(x: body.maxX + 2.5, y: body.minY + h * 0.60)
        )
        path.closeSubpath()

        ctx.addPath(path)
        ctx.setFillColor(style.body.cgColor)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(style.ink.cgColor)
        ctx.strokePath()
    }

    private static func drawFace(in ctx: CGContext, body: CGRect, pose: Pose, style: CreatureStyle) {
        let cx = body.midX
        let h = body.height

        let muzzleW = body.width * 0.46
        let muzzleH = h * 0.28
        let muzzle = CGRect(
            x: cx - muzzleW / 2,
            y: body.minY + h * 0.15,
            width: muzzleW,
            height: muzzleH
        )
        ctx.addEllipse(in: muzzle)
        ctx.setFillColor(style.muzzle.cgColor)
        ctx.fillPath()
        ctx.addEllipse(in: muzzle)
        ctx.setStrokeColor(style.ear.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(1.2)
        ctx.strokePath()
        ctx.setLineWidth(outline)

        let nose = CGRect(x: cx - 5.7, y: muzzle.maxY - 9.6, width: 11.4, height: 8.0)
        ctx.addEllipse(in: nose)
        ctx.setFillColor(style.ink.cgColor)
        ctx.fillPath()
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.7).cgColor)
        ctx.addEllipse(in: CGRect(x: nose.minX + 2.2, y: nose.maxY - 3.6, width: 2.8, height: 2.1))
        ctx.fillPath()

        ctx.setStrokeColor(style.ink.cgColor)
        ctx.setLineWidth(1.9)
        ctx.move(to: CGPoint(x: cx, y: nose.minY))
        ctx.addLine(to: CGPoint(x: cx, y: nose.minY - 2.8))
        ctx.strokePath()
        let mouthY = nose.minY - 2.8
        ctx.move(to: CGPoint(x: cx - 6.0, y: mouthY + 2.2))
        ctx.addQuadCurve(to: CGPoint(x: cx, y: mouthY), control: CGPoint(x: cx - 3.2, y: mouthY - 0.6))
        ctx.addQuadCurve(to: CGPoint(x: cx + 6.0, y: mouthY + 2.2), control: CGPoint(x: cx + 3.2, y: mouthY - 0.6))
        ctx.strokePath()
        ctx.setLineWidth(outline)

        if pose.tongue {
            let tongueRect = CGRect(x: cx - 4.4, y: mouthY - 9.5, width: 8.8, height: 10.5)
            let path = CGPath(roundedRect: tongueRect, cornerWidth: 4.4, cornerHeight: 4.4, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(style.tongue.cgColor)
            ctx.fillPath()
            ctx.addPath(path)
            ctx.setStrokeColor(style.ink.cgColor)
            ctx.setLineWidth(1.8)
            ctx.strokePath()
            ctx.setLineWidth(outline)
        }

        let eyeY = body.minY + h * 0.60
        let dx: CGFloat = 9.5
        ctx.setFillColor(style.ink.cgColor)

        for sign in [CGFloat(-1), 1] {
            let center = CGPoint(x: cx + sign * dx, y: eyeY)
            switch pose.eyes {
            case .open:
                ctx.addEllipse(in: CGRect(x: center.x - 4.7, y: center.y - 5.2, width: 9.4, height: 10.4))
                ctx.fillPath()
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.addEllipse(in: CGRect(x: center.x - 2.6, y: center.y + 0.6, width: 3.6, height: 3.6))
                ctx.fillPath()
                ctx.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
                ctx.addEllipse(in: CGRect(x: center.x + 1.2, y: center.y - 3.2, width: 1.8, height: 1.8))
                ctx.fillPath()
                ctx.setFillColor(style.ink.cgColor)
            case .closed:
                ctx.move(to: CGPoint(x: center.x - 4.5, y: center.y + 1.5))
                ctx.addQuadCurve(
                    to: CGPoint(x: center.x + 4.5, y: center.y + 1.5),
                    control: CGPoint(x: center.x, y: center.y - 3.5)
                )
                ctx.strokePath()
            case .happy:
                ctx.move(to: CGPoint(x: center.x - 4.5, y: center.y - 1.0))
                ctx.addQuadCurve(
                    to: CGPoint(x: center.x + 4.5, y: center.y - 1.0),
                    control: CGPoint(x: center.x, y: center.y + 5.5)
                )
                ctx.strokePath()
            }
        }

        ctx.setFillColor(style.blush.withAlphaComponent(0.5).cgColor)
        for sign in [CGFloat(-1), 1] {
            ctx.addEllipse(in: CGRect(x: cx + sign * 15 - 4.3, y: eyeY - 9.4, width: 8.6, height: 5.2))
        }
        ctx.fillPath()
    }

    private static func drawSleepZ(in ctx: CGContext, anchor: CGPoint, progress: CGFloat, style: CreatureStyle) {
        let alpha = 0.85 - progress * 0.55
        let size = 11 + progress * 7
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: .bold),
            .foregroundColor: style.muzzle.withAlphaComponent(alpha),
            .strokeColor: style.ink.withAlphaComponent(alpha),
            .strokeWidth: -4.0
        ]
        let point = CGPoint(x: anchor.x + progress * 6, y: anchor.y + progress * 12)
        ctx.saveGState()
        ("z" as NSString).draw(at: point, withAttributes: attrs)
        ctx.restoreGState()
    }

    private static func render(size: CGSize, scale: CGFloat, _ body: (CGContext) -> Void) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        let gc = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = gc
        gc.cgContext.setAllowsAntialiasing(true)
        body(gc.cgContext)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}
