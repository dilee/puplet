import AppKit
import SpriteKit

final class PetScene: SKScene {
    private let sprite = SKSpriteNode()
    private var lastUpdate: TimeInterval = 0
    private var animations: [PetState: SKAction] = [:]

    var onFrame: ((TimeInterval) -> Void)?

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        buildAnimations()
        sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sprite.texture = CreatureRenderer.image(for: Pose()).skTexture
        sprite.size = CreatureRenderer.canvas
        addChild(sprite)
        play(.idle)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    func play(_ state: PetState) {
        guard let action = animations[state] else { return }
        sprite.removeAction(forKey: "pose")
        sprite.run(action, withKey: "pose")
    }

    func setFacing(_ facing: CGFloat) {
        sprite.xScale = facing >= 0 ? 1 : -1
    }

    override func update(_ currentTime: TimeInterval) {
        defer { lastUpdate = currentTime }
        guard lastUpdate > 0 else { return }
        let dt = min(currentTime - lastUpdate, 1.0 / 15.0)
        onFrame?(dt)
    }

    private func buildAnimations() {
        var idle = (0..<8).map { index -> Pose in
            let t = CGFloat(index) / 8
            return Pose(
                squash: 1.0 - 0.045 * abs(sin(t * .pi * 2)),
                tailWag: sin(t * .pi * 2) * 0.45
            )
        }
        idle += [
            Pose(squash: 1.0, eyes: .closed, tailWag: 0.2),
            Pose(squash: 1.0, eyes: .closed, tailWag: 0.1)
        ]
        animations[.idle] = loop(idle, timePerFrame: 0.20)

        let walk = (0..<6).map { index -> Pose in
            let t = CGFloat(index) / 6
            return Pose(
                squash: 1.0,
                legPhase: t,
                tailWag: sin(t * .pi * 2),
                earFlop: abs(sin(t * .pi * 2)) * 0.8
            )
        }
        animations[.walk] = loop(walk, timePerFrame: 0.10)

        let sit = [
            Pose(squash: 0.94, eyes: .open, tailWag: 0.35, tucked: true),
            Pose(squash: 0.925, eyes: .open, tailWag: -0.20, tucked: true),
            Pose(squash: 0.94, eyes: .open, tailWag: 0.35, tucked: true),
            Pose(squash: 0.94, eyes: .closed, tailWag: -0.20, tucked: true)
        ]
        animations[.sit] = loop(sit, timePerFrame: 0.42)

        let sleep = (0..<4).map { index in
            Pose(squash: 0.82, eyes: .closed, sleepZ: CGFloat(index) / 3.0, tucked: true)
        }
        animations[.sleep] = loop(sleep, timePerFrame: 0.45)

        let excited = [
            Pose(squash: 0.86, eyes: .happy, tailWag: 1.0, earFlop: 0.2, tongue: true),
            Pose(squash: 1.10, eyes: .happy, tailWag: -0.8, earFlop: 0.9, tongue: true, lift: 5),
            Pose(squash: 1.04, eyes: .happy, tailWag: 0.9, earFlop: 1.0, tongue: true, lift: 9),
            Pose(squash: 0.94, eyes: .happy, tailWag: -0.7, earFlop: 0.4, tongue: true, lift: 2)
        ]
        animations[.excited] = loop(excited, timePerFrame: 0.09)
    }

    private func loop(_ poses: [Pose], timePerFrame: TimeInterval) -> SKAction {
        let textures = poses.map { CreatureRenderer.image(for: $0).skTexture }
        return .repeatForever(.animate(with: textures, timePerFrame: timePerFrame, resize: false, restore: false))
    }
}

private extension NSImage {
    var skTexture: SKTexture { SKTexture(image: self) }
}
