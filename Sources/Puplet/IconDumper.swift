import AppKit

enum IconDumper {
    private struct Recipe {
        var plateInset: CGFloat
        var cornerRadius: CGFloat
        var inkCenterX: CGFloat
        var inkBaseline: CGFloat
        var inkWidth: CGFloat
        var inkHeight: CGFloat
        var outline: CGFloat
        var eyes: EyeShape
        var tailWag: CGFloat
        var earFlop: CGFloat
        var tongue: Bool
        var showShadow: Bool
        var showRim: Bool
        var simplified: Bool = false
        var supersample: Int = 1
    }

    private static let design: CGFloat = 1024

    private static let plateTop = NSColor(srgbRed: 0.36, green: 0.65, blue: 0.70, alpha: 1)
    private static let plateBottom = NSColor(srgbRed: 0.18, green: 0.42, blue: 0.51, alpha: 1)
    private static let shadowInk = NSColor(srgbRed: 0.05, green: 0.16, blue: 0.20, alpha: 1)

    private static func recipe(for pixels: Int) -> Recipe {
        switch pixels {
        case ...16:
            return Recipe(plateInset: 60, cornerRadius: 200, inkCenterX: 500, inkBaseline: 245,
                          inkWidth: 900, inkHeight: 660, outline: 3.4, eyes: .open,
                          tailWag: 0.4, earFlop: 0.6, tongue: true,
                          showShadow: false, showRim: false, simplified: true, supersample: 8)
        case ...32:
            return Recipe(plateInset: 96, cornerRadius: 188, inkCenterX: 505, inkBaseline: 295,
                          inkWidth: 700, inkHeight: 520, outline: 3.6, eyes: .happy,
                          tailWag: 0.7, earFlop: 0.8, tongue: true,
                          showShadow: false, showRim: false, supersample: 8)
        case ...64:
            return Recipe(plateInset: 100, cornerRadius: 186, inkCenterX: 528, inkBaseline: 262,
                          inkWidth: 740, inkHeight: 600, outline: 3.0, eyes: .happy,
                          tailWag: 0.9, earFlop: 1.0, tongue: true,
                          showShadow: false, showRim: true, supersample: 4)
        default:
            return Recipe(plateInset: 100, cornerRadius: 186, inkCenterX: 528, inkBaseline: 262,
                          inkWidth: 740, inkHeight: 600, outline: 2.6, eyes: .happy,
                          tailWag: 0.9, earFlop: 1.0, tongue: true,
                          showShadow: true, showRim: true)
        }
    }

    private static func pose(_ recipe: Recipe) -> Pose {
        Pose(
            squash: 1.04,
            eyes: recipe.eyes,
            tailWag: recipe.tailWag,
            earFlop: recipe.earFlop,
            tongue: recipe.tongue
        )
    }

    private static func style(_ recipe: Recipe) -> CreatureStyle {
        var style = CreatureStyle.default
        style.outline = recipe.outline
        style.simplified = recipe.simplified
        return style
    }

    static func run(into directory: String) {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let variants: [(String, Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]

        var written = 0
        for (name, pixels) in variants {
            if write(image(pixels: pixels), to: url.appendingPathComponent("\(name).png")) {
                written += 1
            }
        }

        print("wrote \(written) icon sizes to \(url.path)")
    }

    static func image(pixels: Int) -> NSImage {
        let recipe = recipe(for: pixels)
        let side = CGFloat(pixels)
        let rendered = CGFloat(pixels * recipe.supersample)

        let full = CreatureRenderer.render(size: CGSize(width: rendered, height: rendered), scale: 1) { ctx in
            ctx.scaleBy(x: rendered / design, y: rendered / design)
            draw(recipe, in: ctx)
        }

        guard recipe.supersample > 1,
              let cg = full.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return full }

        return CreatureRenderer.render(size: CGSize(width: side, height: side), scale: 1) { ctx in
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    private static func draw(_ recipe: Recipe, in ctx: CGContext) {
        let plate = CGRect(x: recipe.plateInset, y: recipe.plateInset,
                           width: design - recipe.plateInset * 2,
                           height: design - recipe.plateInset * 2)
        let shape = CGPath(roundedRect: plate,
                           cornerWidth: recipe.cornerRadius,
                           cornerHeight: recipe.cornerRadius,
                           transform: nil)

        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [plateTop.cgColor, plateBottom.cgColor] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: plate.midX, y: plate.maxY),
            end: CGPoint(x: plate.midX, y: plate.minY),
            options: []
        )
        ctx.restoreGState()

        if recipe.showRim {
            ctx.addPath(CGPath(roundedRect: plate.insetBy(dx: 1.5, dy: 1.5),
                               cornerWidth: recipe.cornerRadius - 1.5,
                               cornerHeight: recipe.cornerRadius - 1.5,
                               transform: nil))
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
            ctx.setLineWidth(3)
            ctx.strokePath()
        }

        if recipe.showShadow {
            let ellipse = CGRect(x: recipe.inkCenterX - 285, y: recipe.inkBaseline - 34,
                                 width: 530, height: 68)
            let shadow = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    shadowInk.withAlphaComponent(0.32).cgColor,
                    shadowInk.withAlphaComponent(0).cgColor,
                ] as CFArray,
                locations: [0, 1]
            )!
            ctx.saveGState()
            ctx.addEllipse(in: ellipse)
            ctx.clip()
            ctx.translateBy(x: ellipse.midX, y: ellipse.midY)
            ctx.scaleBy(x: 1, y: ellipse.height / ellipse.width)
            ctx.drawRadialGradient(
                shadow,
                startCenter: .zero, startRadius: 0,
                endCenter: .zero, endRadius: ellipse.width / 2,
                options: []
            )
            ctx.restoreGState()
        }

        let style = style(recipe)
        let pose = pose(recipe)
        let ink = inkBounds(pose: pose, style: style)
        let scale = min(recipe.inkWidth / ink.width, recipe.inkHeight / ink.height)

        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        ctx.translateBy(
            x: recipe.inkCenterX - ink.midX * scale,
            y: recipe.inkBaseline - ink.minY * scale
        )
        ctx.scaleBy(x: scale, y: scale)
        CreatureRenderer.draw(pose: pose, style: style, in: ctx)
        ctx.restoreGState()
    }

    private static func inkBounds(pose: Pose, style: CreatureStyle) -> CGRect {
        let scale: CGFloat = 8
        let width = Int(CreatureRenderer.canvas.width * scale)
        let height = Int(CreatureRenderer.canvas.height * scale)
        let fallback = CGRect(origin: .zero, size: CreatureRenderer.canvas)

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var bounds = fallback

        pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }

            ctx.scaleBy(x: scale, y: scale)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            CreatureRenderer.draw(pose: pose, style: style, in: ctx)
            NSGraphicsContext.restoreGraphicsState()

            var minX = width, minY = height, maxX = -1, maxY = -1
            for row in 0..<height {
                for column in 0..<width where buffer[(row * width + column) * 4 + 3] > 8 {
                    let y = height - 1 - row
                    minX = min(minX, column)
                    maxX = max(maxX, column)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
            guard maxX >= minX, maxY >= minY else { return }

            bounds = CGRect(
                x: CGFloat(minX) / scale,
                y: CGFloat(minY) / scale,
                width: CGFloat(maxX - minX + 1) / scale,
                height: CGFloat(maxY - minY + 1) / scale
            )
        }

        return bounds
    }

    private static func write(_ image: NSImage, to url: URL) -> Bool {
        guard
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else { return false }
        return (try? png.write(to: url)) != nil
    }
}
