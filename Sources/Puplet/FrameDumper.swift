import AppKit

enum FrameDumper {
    static func run(into directory: String) {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        var sheet: [(String, [Pose])] = []
        sheet.append(("idle", [
            Pose(squash: 1.0, tailWag: 0.45),
            Pose(squash: 0.955, tailWag: -0.45),
            Pose(squash: 1.0, eyes: .closed, tailWag: 0.2)
        ]))
        sheet.append(("walk", (0..<6).map { index -> Pose in
            let t = CGFloat(index) / 6
            return Pose(squash: 1.0, legPhase: t, tailWag: sin(t * .pi * 2), earFlop: abs(sin(t * .pi * 2)) * 0.8)
        }))
        sheet.append(("sit", [
            Pose(squash: 0.94, tailWag: 0.35, tucked: true),
            Pose(squash: 0.94, eyes: .closed, tailWag: -0.2, tucked: true)
        ]))
        sheet.append(("sleep", (0..<4).map { Pose(squash: 0.82, eyes: .closed, sleepZ: CGFloat($0) / 3.0, tucked: true) }))
        sheet.append(("excited", [
            Pose(squash: 0.86, eyes: .happy, tailWag: 1.0, earFlop: 0.2, tongue: true),
            Pose(squash: 1.10, eyes: .happy, tailWag: -0.8, earFlop: 0.9, tongue: true, lift: 5),
            Pose(squash: 1.04, eyes: .happy, tailWag: 0.9, earFlop: 1.0, tongue: true, lift: 9)
        ]))

        var written = 0
        for (name, poses) in sheet {
            for (index, pose) in poses.enumerated() {
                let image = CreatureRenderer.image(for: pose)
                let target = url.appendingPathComponent("\(name)-\(index).png")
                if write(image, to: target) { written += 1 }
            }
        }

        if let contact = contactSheet(sheet.flatMap(\.1)) {
            _ = write(contact, to: url.appendingPathComponent("contact-sheet.png"))
        }

        print("wrote \(written) frames + contact sheet to \(url.path)")
    }

    private static func contactSheet(_ poses: [Pose]) -> NSImage? {
        let columns = 6
        let cell = CreatureRenderer.canvas
        let rows = Int(ceil(Double(poses.count) / Double(columns)))
        let size = CGSize(width: cell.width * CGFloat(columns), height: cell.height * CGFloat(rows))

        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(srgbRed: 0.62, green: 0.72, blue: 0.80, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        for (index, pose) in poses.enumerated() {
            let column = index % columns
            let row = index / columns
            let point = CGPoint(
                x: CGFloat(column) * cell.width,
                y: size.height - CGFloat(row + 1) * cell.height
            )
            CreatureRenderer.image(for: pose).draw(at: point, from: .zero, operation: .sourceOver, fraction: 1)
        }
        image.unlockFocus()
        return image
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
