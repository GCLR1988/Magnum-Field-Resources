import Foundation
import CoreGraphics

/// Fixed world coordinates keep difficulty the same on every device and orientation.
struct HardHatGame {
    enum Phase { case ready, playing, paused, ended }
    struct Gate: Identifiable {
        let id: Int
        var x: Double
        let center: Double
        let gap: Double
        var passed = false
    }

    static let width = 390.0
    static let height = 640.0
    static let floor = 48.0
    static let playerX = 100.0
    static let radius = 14.0
    static let gateWidth = 58.0
    private(set) var phase: Phase = .ready
    private(set) var y = 340.0
    private(set) var velocity = 0.0
    private(set) var score = 0
    private(set) var gates: [Gate] = []
    private var nextID = 0

    mutating func start() {
        self = HardHatGame()
        phase = .playing
        flap()
    }

    mutating func flap() {
        guard phase == .playing else { return }
        velocity = 290
    }

    mutating func pause() {
        if phase == .playing { phase = .paused }
    }

    mutating func resume() {
        if phase == .paused { phase = .playing }
    }

    /// Discard long frame stalls instead of making the player fall while the app is suspended.
    mutating func advance(_ elapsed: Double, nextCenter: () -> Double = { Double.random(in: 205...465) }) {
        guard phase == .playing, elapsed.isFinite, elapsed > 0 else { return }
        let dt = min(elapsed, 1.0 / 30.0)
        velocity -= 760 * dt
        y += velocity * dt
        let speed = min(160 + Double(score) * 2, 220)
        for index in gates.indices { gates[index].x -= speed * dt }
        if gates.last.map({ $0.x < Self.width - 175 }) ?? true {
            let gap = max(150, 185 - Double(score))
            // Clamp externally supplied centers too, keeping both sides of the gap playable.
            let center = min(max(nextCenter(), Self.floor + gap / 2 + 60), Self.height - gap / 2 - 60)
            gates.append(Gate(id: nextID, x: Self.width + 35, center: center, gap: gap))
            nextID += 1
        }
        if y - Self.radius <= Self.floor || y + Self.radius >= Self.height {
            phase = .ended
            return
        }
        for gate in gates {
            let lower = CGRect(x: gate.x, y: Self.floor, width: Self.gateWidth,
                               height: gate.center - gate.gap / 2 - Self.floor)
            let upper = CGRect(x: gate.x, y: gate.center + gate.gap / 2,
                               width: Self.gateWidth, height: Self.height - gate.center - gate.gap / 2)
            if touches(lower) || touches(upper) {
                phase = .ended
                return
            }
        }
        for index in gates.indices where !gates[index].passed
            && gates[index].x + Self.gateWidth < Self.playerX - Self.radius {
            gates[index].passed = true
            score += 1
        }
        gates.removeAll { $0.x + Self.gateWidth < -10 }
    }

    private func touches(_ rect: CGRect) -> Bool {
        let dx = Self.playerX - min(max(Self.playerX, rect.minX), rect.maxX)
        let dy = y - min(max(y, rect.minY), rect.maxY)
        return dx * dx + dy * dy <= Self.radius * Self.radius
    }
}
