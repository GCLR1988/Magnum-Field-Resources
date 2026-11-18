import SpriteKit
import UIKit

/// Presentation only: HardHatGame remains the authority for physics, hit boxes and scoring.
final class HardHatScene: SKScene {
    let status = HardHatStatus()
    let feedback = HardHatFeedback()
    var recordToBeat = 0
    private var game = HardHatGame()
    private let drone = SKNode()
    private let rotor = SKShapeNode(ellipseOf: CGSize(width: 53, height: 4))
    private let obstacles = SKNode()
    private let effects = SKNode()
    private let farSite = SKNode()
    private let nearSite = SKNode()
    private var gateNodes: [Int: SKNode] = [:]
    private var previousTime: TimeInterval?
    private var sceneryDistance: CGFloat = 0
    private var trailTime: TimeInterval = 0
    private var motionTime: TimeInterval = 0
    private var reduceMotion = false
    private let burgundy = UIColor(red: 120 / 255, green: 35 / 255, blue: 47 / 255, alpha: 1)
    private let gold = UIColor(red: 0.97, green: 0.73, blue: 0.27, alpha: 1)
    private let steel = UIColor(red: 0.23, green: 0.24, blue: 0.26, alpha: 1)

    override init() {
        super.init(size: CGSize(width: HardHatGame.width, height: HardHatGame.height))
        scaleMode = .aspectFit
        backgroundColor = UIColor(red: 0.95, green: 0.91, blue: 0.85, alpha: 1)
        buildSite()
    }

    required init?(coder: NSCoder) { nil }

    func configure(sound: Bool, haptics: Bool, reduceMotion: Bool, best: Int) {
        self.reduceMotion = reduceMotion
        recordToBeat = best
        feedback.configure(sound: sound, haptics: haptics)
        if reduceMotion {
            effects.removeAllChildren()
            rotor.xScale = 1
        }
    }

    override func didMove(to view: SKView) {
        if status.phase == .ready { startGame() }
    }

    func startGame() {
        game.start()
        status.runID = UUID()
        status.score = 0
        status.newBest = false
        status.phase = .playing
        obstacles.removeAllChildren()
        effects.removeAllChildren()
        gateNodes.removeAll()
        previousTime = nil
        trailTime = 0
        drone.position = CGPoint(x: HardHatGame.playerX, y: game.y)
        drone.zRotation = 0
    }

    func flap() {
        guard game.phase == .playing else { return }
        game.flap()
        feedback.play(.boost)
        guard !reduceMotion else { return }
        for index in 0..<4 {
            puff(at: CGPoint(x: drone.position.x - 15, y: drone.position.y - CGFloat(index * 3)),
                 color: .white.withAlphaComponent(0.65), radius: 3, dx: -22, dy: -12 - CGFloat(index * 3))
        }
    }

    func pauseGame() {
        game.pause()
        status.phase = game.phase
        previousTime = nil
        feedback.pause()
    }

    func resumeGame() {
        game.resume()
        status.phase = game.phase
        previousTime = nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { flap() }

    override func update(_ currentTime: TimeInterval) {
        defer { previousTime = currentTime }
        guard let previousTime, game.phase == .playing else { return }
        let elapsed = max(0, min(currentTime - previousTime, 1.0 / 30.0))
        let oldScore = game.score
        game.advance(currentTime - previousTime)
        drone.position = CGPoint(x: HardHatGame.playerX, y: game.y)
        drone.zRotation = reduceMotion ? 0 : max(-0.5, min(0.35, game.velocity / 650))
        if !reduceMotion {
            motionTime += elapsed
            sceneryDistance += CGFloat(elapsed * min(160 + Double(game.score) * 2, 220))
            farSite.position.x = -(sceneryDistance * 0.08).truncatingRemainder(dividingBy: 390)
            nearSite.position.x = -(sceneryDistance * 0.22).truncatingRemainder(dividingBy: 390)
            rotor.xScale = 0.45 + abs(sin(motionTime * 35)) * 0.55
            trailTime += elapsed
            if trailTime >= 0.08 {
                trailTime = 0
                puff(at: CGPoint(x: drone.position.x - 22, y: drone.position.y),
                     color: gold.withAlphaComponent(0.4), radius: 2, dx: -35, dy: -3)
            }
        }
        for gate in game.gates {
            if gateNodes[gate.id] == nil {
                let node = SKNode()
                addScaffold(to: node, bottom: HardHatGame.floor, top: gate.center - gate.gap / 2)
                addScaffold(to: node, bottom: gate.center + gate.gap / 2, top: HardHatGame.height)
                obstacles.addChild(node)
                gateNodes[gate.id] = node
            }
            gateNodes[gate.id]?.position.x = gate.x
        }
        let ids = Set(game.gates.map(\.id))
        for id in Array(gateNodes.keys) where !ids.contains(id) {
            gateNodes.removeValue(forKey: id)?.removeFromParent()
        }
        if game.score != oldScore {
            status.score = game.score
            let record = game.score > recordToBeat && !status.newBest
            if record { status.newBest = true }
            feedback.play(.score)
            if record || game.score.isMultiple(of: 5) {
                status.celebration += 1
                celebrate()
            }
        }
        if game.phase == .ended {
            feedback.play(.impact)
        }
        if status.phase != game.phase { status.phase = game.phase }
    }

    private func puff(at point: CGPoint, color: UIColor, radius: CGFloat, dx: CGFloat, dy: CGFloat) {
        guard effects.children.count < 48 else { return }
        let node = SKShapeNode(circleOfRadius: radius)
        node.fillColor = color
        node.strokeColor = .clear
        node.position = point
        effects.addChild(node)
        node.run(.sequence([
            .group([.moveBy(x: dx, y: dy, duration: 0.45), .fadeOut(withDuration: 0.45),
                    .scale(to: 0.2, duration: 0.45)]),
            .removeFromParent()
        ]))
    }

    private func celebrate() {
        guard !reduceMotion else { return }
        for index in 0..<16 {
            let angle = CGFloat(index) * .pi * 2 / 16
            puff(at: drone.position, color: index.isMultiple(of: 2) ? gold : .white,
                 radius: 2.5, dx: cos(angle) * 65, dy: sin(angle) * 65)
        }
    }

    private func rectangle(_ rect: CGRect, color: UIColor, parent: SKNode, radius: CGFloat = 2) {
        let node = SKShapeNode(rect: rect, cornerRadius: radius)
        node.fillColor = color
        node.strokeColor = .clear
        parent.addChild(node)
    }

    private func line(from start: CGPoint, to end: CGPoint, color: UIColor, width: CGFloat, parent: SKNode) {
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)
        let node = SKShapeNode(path: path)
        node.strokeColor = color
        node.lineWidth = width
        parent.addChild(node)
    }

    private func buildSite() {
        let skyImage = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor(red: 0.76, green: 0.65, blue: 0.65, alpha: 1).cgColor,
                          UIColor(red: 0.98, green: 0.94, blue: 0.85, alpha: 1).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors as CFArray, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero,
                    end: CGPoint(x: 0, y: size.height), options: [])
            }
            UIColor.white.withAlphaComponent(0.18).setFill()
            UIBezierPath(ovalIn: CGRect(x: 240, y: 55, width: 100, height: 100)).fill()
            UIColor(red: 1, green: 0.94, blue: 0.79, alpha: 0.8).setFill()
            UIBezierPath(ovalIn: CGRect(x: 263, y: 78, width: 54, height: 54)).fill()
        }
        let sky = SKSpriteNode(texture: SKTexture(image: skyImage), size: size)
        sky.anchorPoint = .zero
        addChild(sky)
        farSite.zPosition = 1
        nearSite.zPosition = 2
        addChild(farSite)
        addChild(nearSite)
        for tile in 0..<2 {
            let offset = CGFloat(tile * 390)
            for index in 0..<6 {
                let x = offset + CGFloat(index * 70)
                let height = CGFloat(80 + (index * 43) % 100)
                let color = burgundy.withAlphaComponent(0.10)
                rectangle(CGRect(x: x, y: 48, width: 52, height: height), color: color, parent: farSite)
                for window in stride(from: 60, to: Int(height + 40), by: 18) {
                    rectangle(CGRect(x: x + 8, y: CGFloat(window), width: 5, height: 7),
                              color: .white.withAlphaComponent(0.25), parent: farSite)
                    rectangle(CGRect(x: x + 25, y: CGFloat(window), width: 5, height: 7),
                              color: .white.withAlphaComponent(0.25), parent: farSite)
                }
            }
            addCrane(at: offset + 270, parent: nearSite)
            rectangle(CGRect(x: offset + 15, y: 48, width: 75, height: 68),
                      color: steel.withAlphaComponent(0.17), parent: nearSite)
            for index in 0..<5 {
                rectangle(CGRect(x: offset + 22 + CGFloat(index * 13), y: 54, width: 3, height: 54),
                          color: .white.withAlphaComponent(0.22), parent: nearSite)
            }
        }
        obstacles.zPosition = 5
        addChild(obstacles)
        let ground = SKNode()
        ground.zPosition = 8
        rectangle(CGRect(x: 0, y: 0, width: 390, height: 48), color: steel, parent: ground)
        rectangle(CGRect(x: 0, y: 39, width: 390, height: 9), color: burgundy, parent: ground)
        rectangle(CGRect(x: 0, y: 47, width: 390, height: 1), color: .white.withAlphaComponent(0.7), parent: ground)
        for x in stride(from: 0, to: 390, by: 28) {
            line(from: CGPoint(x: x, y: 40), to: CGPoint(x: x + 12, y: 47),
                 color: gold, width: 4, parent: ground)
            rectangle(CGRect(x: x + 5, y: 12, width: 14, height: 2),
                      color: .white.withAlphaComponent(0.12), parent: ground)
        }
        addChild(ground)
        buildDrone()
        drone.zPosition = 10
        addChild(drone)
        effects.zPosition = 9
        addChild(effects)
    }

    private func addCrane(at x: CGFloat, parent: SKNode) {
        let ink = burgundy.withAlphaComponent(0.20)
        line(from: CGPoint(x: x, y: 48), to: CGPoint(x: x, y: 460), color: ink, width: 7, parent: parent)
        line(from: CGPoint(x: x - 90, y: 440), to: CGPoint(x: x + 105, y: 440), color: ink, width: 6, parent: parent)
        line(from: CGPoint(x: x - 80, y: 440), to: CGPoint(x: x, y: 490), color: ink, width: 2, parent: parent)
        line(from: CGPoint(x: x, y: 490), to: CGPoint(x: x + 95, y: 440), color: ink, width: 2, parent: parent)
        line(from: CGPoint(x: x + 85, y: 440), to: CGPoint(x: x + 85, y: 300), color: ink, width: 1.5, parent: parent)
        for y in stride(from: 60, to: 430, by: 30) {
            line(from: CGPoint(x: x - 5, y: CGFloat(y)), to: CGPoint(x: x + 5, y: CGFloat(y + 20)),
                 color: ink, width: 2, parent: parent)
        }
    }

    private func buildDrone() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 80)).image { context in
            let cg = context.cgContext
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 4), blur: 6, color: UIColor.black.withAlphaComponent(0.25).cgColor)
            gold.setFill()
            UIBezierPath(ovalIn: CGRect(x: 16, y: 12, width: 68, height: 55)).fill()
            cg.restoreGState()
            cg.saveGState()
            UIBezierPath(ovalIn: CGRect(x: 16, y: 12, width: 68, height: 55)).addClip()
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor(red: 1, green: 0.91, blue: 0.56, alpha: 1).cgColor, gold.cgColor,
                         UIColor(red: 0.72, green: 0.42, blue: 0.10, alpha: 1).cgColor] as CFArray,
                locations: [0, 0.5, 1]) {
                cg.drawLinearGradient(gradient, start: CGPoint(x: 25, y: 10), end: CGPoint(x: 80, y: 72), options: [])
            }
            cg.restoreGState()
            UIColor.white.withAlphaComponent(0.55).setFill()
            UIBezierPath(roundedRect: CGRect(x: 27, y: 20, width: 8, height: 24), cornerRadius: 4).fill()
            burgundy.setFill()
            UIBezierPath(roundedRect: CGRect(x: 7, y: 57, width: 86, height: 11), cornerRadius: 5).fill()
            UIColor.white.withAlphaComponent(0.25).setFill()
            UIBezierPath(roundedRect: CGRect(x: 13, y: 58, width: 73, height: 2), cornerRadius: 1).fill()
            burgundy.setFill()
            UIBezierPath(roundedRect: CGRect(x: 42, y: 29, width: 23, height: 24), cornerRadius: 5).fill()
            ("M" as NSString).draw(at: CGPoint(x: 46, y: 30), withAttributes: [
                .font: UIFont.systemFont(ofSize: 18, weight: .black), .foregroundColor: UIColor.white
            ])
        }
        let body = SKSpriteNode(texture: SKTexture(image: image), size: CGSize(width: 47, height: 38))
        drone.addChild(body)
        line(from: CGPoint(x: 0, y: 15), to: CGPoint(x: 0, y: 22), color: steel, width: 3, parent: drone)
        rotor.position.y = 23
        rotor.fillColor = steel
        rotor.strokeColor = .white.withAlphaComponent(0.5)
        rotor.lineWidth = 0.6
        drone.addChild(rotor)
    }

    private func addScaffold(to parent: SKNode, bottom: Double, top: Double) {
        let height = top - bottom
        guard height > 0 else { return }
        // Visual edges exactly match the model's 58-point obstacle width.
        rectangle(CGRect(x: 0, y: bottom, width: 58, height: height), color: burgundy, parent: parent)
        rectangle(CGRect(x: 4, y: bottom, width: 4, height: height), color: .white.withAlphaComponent(0.2), parent: parent)
        rectangle(CGRect(x: 50, y: bottom, width: 8, height: height), color: .black.withAlphaComponent(0.18), parent: parent)
        for x in [10.0, 45.0] {
            rectangle(CGRect(x: x, y: bottom, width: 3, height: height), color: steel, parent: parent)
            rectangle(CGRect(x: x, y: bottom, width: 1, height: height), color: .white.withAlphaComponent(0.4), parent: parent)
        }
        for y in stride(from: bottom + 12, to: top - 12, by: 36) {
            let endY = min(y + 28, top - 12)
            line(from: CGPoint(x: 13, y: y), to: CGPoint(x: 45, y: endY), color: steel, width: 3, parent: parent)
            line(from: CGPoint(x: 45, y: y), to: CGPoint(x: 13, y: endY), color: .white.withAlphaComponent(0.3), width: 1.5, parent: parent)
            for x in [11.5, 46.5] {
                let bolt = SKShapeNode(circleOfRadius: 1.5)
                bolt.position = CGPoint(x: x, y: y)
                bolt.fillColor = .lightGray
                bolt.strokeColor = .clear
                parent.addChild(bolt)
            }
        }
        for y in [bottom, top - 10] {
            rectangle(CGRect(x: 0, y: y, width: 58, height: 10), color: steel, parent: parent)
            for x in stride(from: 3, to: 50, by: 13) {
                line(from: CGPoint(x: Double(x), y: y + 2), to: CGPoint(x: Double(x + 7), y: y + 8),
                     color: gold, width: 4, parent: parent)
            }
            line(from: CGPoint(x: 0, y: y + 9), to: CGPoint(x: 58, y: y + 9),
                 color: .white.withAlphaComponent(0.5), width: 1, parent: parent)
        }
    }
}
