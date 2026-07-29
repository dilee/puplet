import Foundation

enum PetState: String, CaseIterable {
    case idle
    case walk
    case sit
    case sleep
    case excited
}

final class BehaviorMachine {
    private(set) var state: PetState = .idle
    private(set) var facing: CGFloat = 1

    var onEnter: ((PetState) -> Void)?

    private var remaining: TimeInterval = 1.5

    private static let transitions: [PetState: [(PetState, Double)]] = [
        .idle: [(.walk, 0.45), (.sit, 0.25), (.idle, 0.20), (.sleep, 0.10)],
        .walk: [(.idle, 0.45), (.walk, 0.30), (.sit, 0.25)],
        .sit: [(.idle, 0.50), (.sit, 0.25), (.sleep, 0.25)],
        .sleep: [(.sleep, 0.55), (.idle, 0.45)],
        .excited: [(.idle, 1.0)]
    ]

    private static func duration(for state: PetState) -> TimeInterval {
        switch state {
        case .idle: return .random(in: 2.0...5.0)
        case .walk: return .random(in: 2.5...6.5)
        case .sit: return .random(in: 3.0...8.0)
        case .sleep: return .random(in: 10.0...25.0)
        case .excited: return 1.6
        }
    }

    func step(_ dt: TimeInterval) {
        remaining -= dt
        guard remaining <= 0 else { return }
        advance()
    }

    func force(_ next: PetState, flipFacing: Bool = false) {
        if flipFacing { facing *= -1 }
        enter(next)
    }

    func turnAround() {
        facing *= -1
    }

    private func advance() {
        let options = Self.transitions[state] ?? [(.idle, 1.0)]
        let total = options.reduce(0) { $0 + $1.1 }
        var roll = Double.random(in: 0..<total)
        var next = options[0].0
        for (candidate, weight) in options {
            if roll < weight {
                next = candidate
                break
            }
            roll -= weight
        }
        if next == .walk {
            facing = Bool.random() ? 1 : -1
        }
        enter(next)
    }

    private func enter(_ next: PetState) {
        state = next
        remaining = Self.duration(for: next)
        onEnter?(next)
    }
}
