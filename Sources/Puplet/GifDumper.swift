import AppKit
import ImageIO
import UniformTypeIdentifiers

enum GifDumper {
    private struct Shot {
        var pose: Pose
        var x: CGFloat
        var bubble: String?
        var delay: Double
    }

    private static let canvas = CGSize(width: 480, height: 172)
    private static let petGround: CGFloat = 2

    static func run(to path: String) {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let shots = storyboard()
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, shots.count, nil
        ) else {
            print("could not create \(url.path)")
            exit(1)
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)

        for shot in shots {
            guard let image = render(shot) else { continue }
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: shot.delay,
                    kCGImagePropertyGIFUnclampedDelayTime: shot.delay
                ]
            ] as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            print("failed to write \(url.path)")
            exit(1)
        }
        print("wrote \(shots.count) frames to \(url.path)")
    }

    private static func storyboard() -> [Shot] {
        var shots: [Shot] = []
        let restX: CGFloat = 192

        for i in 0..<14 {
            let t = CGFloat(i % 6) / 6
            let progress = CGFloat(i) / 13
            shots.append(Shot(
                pose: Pose(legPhase: t, tailWag: sin(t * 2 * .pi), earFlop: abs(sin(t * 2 * .pi)) * 0.8),
                x: -40 + progress * (restX + 40),
                bubble: nil,
                delay: 0.09
            ))
        }

        for i in 0..<10 {
            shots.append(Shot(
                pose: Pose(
                    squash: i % 2 == 0 ? 1.0 : 0.955,
                    eyes: i == 7 ? .closed : .open,
                    tailWag: i % 2 == 0 ? 0.45 : -0.45
                ),
                x: restX,
                bubble: "oh hey, you're back!",
                delay: 0.14
            ))
        }

        let reply = "you love coffee. i remember."
        let words = reply.split(separator: " ")
        for i in 1...words.count {
            shots.append(Shot(
                pose: Pose(squash: 0.94, tailWag: i % 2 == 0 ? 0.35 : -0.2, tucked: true),
                x: restX,
                bubble: words.prefix(i).joined(separator: " "),
                delay: 0.28
            ))
        }
        for i in 0..<8 {
            shots.append(Shot(
                pose: Pose(squash: 0.94, tailWag: i % 2 == 0 ? 0.35 : -0.2, tucked: true),
                x: restX,
                bubble: reply,
                delay: 0.14
            ))
        }

        let excited = [
            Pose(squash: 0.86, eyes: .happy, tailWag: 1.0, earFlop: 0.2, tongue: true),
            Pose(squash: 1.10, eyes: .happy, tailWag: -0.8, earFlop: 0.9, tongue: true, lift: 5),
            Pose(squash: 1.04, eyes: .happy, tailWag: 0.9, earFlop: 1.0, tongue: true, lift: 9),
            Pose(squash: 0.94, eyes: .happy, tailWag: -0.7, earFlop: 0.4, tongue: true, lift: 2)
        ]
        for i in 0..<8 {
            shots.append(Shot(pose: excited[i % excited.count], x: restX, bubble: nil, delay: 0.1))
        }

        for i in 0..<10 {
            shots.append(Shot(
                pose: Pose(squash: 0.82, eyes: .closed, sleepZ: CGFloat(i % 4) / 3, tucked: true),
                x: restX,
                bubble: nil,
                delay: 0.16
            ))
        }
        shots.append(Shot(
            pose: Pose(squash: 0.82, eyes: .closed, sleepZ: 0.33, tucked: true),
            x: restX,
            bubble: nil,
            delay: 0.7
        ))

        return shots
    }

    private static func render(_ shot: Shot) -> CGImage? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvas.width * 2),
            pixelsHigh: Int(canvas.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = canvas

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let gc = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = gc
        let ctx = gc.cgContext
        ctx.setAllowsAntialiasing(true)

        ctx.setFillColor(NSColor(srgbRed: 0.62, green: 0.72, blue: 0.80, alpha: 1).cgColor)
        ctx.fill(CGRect(origin: .zero, size: canvas))
        ctx.setFillColor(NSColor(srgbRed: 0.56, green: 0.65, blue: 0.73, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: canvas.width, height: 14))

        let pet = CreatureRenderer.image(for: shot.pose)
        pet.draw(
            at: NSPoint(x: shot.x, y: petGround),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )

        if let bubble = shot.bubble {
            let size = BubbleView.size(for: bubble)
            var origin = NSPoint(x: shot.x + 48 - size.width / 2, y: petGround + 96 - 14)
            origin.x = min(max(origin.x, 4), canvas.width - size.width - 4)
            BubbleView.draw(text: bubble, in: NSRect(origin: origin, size: size), ctx: ctx)
        }

        return rep.cgImage
    }
}
