import SwiftUI
import SpriteKit
import Observation

@MainActor
@Observable
final class HardHatStatus {
    var phase: HardHatGame.Phase = .ready
    var score = 0
    var runID = UUID()
}

struct HardHatGameView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var scene = HardHatScene()
    @State private var scores = HardHatScores()
    @State private var name = ""
    @State private var saved = false
    @State private var showingScores = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("\(scene.status.score)", systemImage: "flag.checkered")
                    .accessibilityLabel("Score: \(scene.status.score)")
                Spacer()
                Label("Best: \(scores.best)", systemImage: "trophy.fill")
                    .foregroundStyle(AppStyle.accent)
            }
            .font(.headline.monospacedDigit())
            .padding(.horizontal)

            GeometryReader { geometry in
                SpriteView(scene: scene, isPaused: scene.status.phase == .paused || scene.status.phase == .ended || scenePhase != .active)
                    .aspectRatio(390.0 / 640.0, contentMode: .fit)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .accessibilityLabel("Hard Hat Hop play area")
                    .accessibilityHint("Double tap to boost the drone.")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { scene.flap() }
            }
            .overlay {
                if scene.status.phase == .paused || scene.status.phase == .ended {
                    ScrollView {
                        gameMenu
                            .padding(20)
                            .frame(maxWidth: 340)
                            .frame(maxWidth: .infinity)
                    }
                    .defaultScrollAnchor(.center)
                    .background(.black.opacity(0.20))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadius))

            Text("Tap to fly. Dodge the scaffolding.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(AppStyle.background)
        .navigationTitle("Hard Hat Hop")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("High Scores", systemImage: "trophy") {
                    scene.pauseGame()
                    showingScores = true
                }
                if scene.status.phase == .playing {
                    Button("Pause", systemImage: "pause.fill") { scene.pauseGame() }
                }
            }
        }
        .sheet(isPresented: $showingScores) {
            NavigationStack {
                List {
                    Section {
                        Label("Best: \(scores.best)", systemImage: "trophy.fill")
                            .font(.headline)
                            .foregroundStyle(AppStyle.accent)
                        ForEach(scores.entries) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.name).font(.headline)
                                    Text(entry.date, format: .dateTime.month().day().year())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(entry.score, format: .number)
                                    .font(.title3.bold().monospacedDigit())
                            }
                        }
                        if scores.entries.isEmpty {
                            Text("Finish a run and save your name to join the leaderboard.")
                                .foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("Top 10 scores on this device. Your best score is saved automatically.")
                    }
                }
                .navigationTitle("Site Legends")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingScores = false }
                    }
                }
            }
        }
        .onChange(of: scene.status.phase) { _, phase in
            if phase == .ended { scores.recordBest(scene.status.score) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { scene.pauseGame() }
        }
        .onDisappear { scene.pauseGame() }
    }

    @ViewBuilder
    private var gameMenu: some View {
        VStack(spacing: 16) {
            Image(systemName: scene.status.phase == .ended ? "cone.fill" : "hammer.fill")
                .font(.largeTitle)
                .foregroundStyle(AppStyle.accent)
            if scene.status.phase == .paused {
                Text("On Break").font(.title2.bold())
                Button("Resume") { scene.resumeGame() }
                    .buttonStyle(.borderedProminent)
            } else {
                Text("Site Closed!").font(.title2.bold())
                Text("Score: \(scene.status.score)")
                    .font(.title3.monospacedDigit())
                TextField("Your name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .disabled(saved)
                    .onChange(of: name) { _, value in name = String(value.prefix(24)) }
                    .onSubmit { saveScore() }
                Button(saved ? "Score Saved" : "Save Score") { saveScore() }
                    .buttonStyle(.bordered)
                    .disabled(saved || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Try Again") { start() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .tint(AppStyle.accent)
        .padding(24)
        .frame(maxWidth: .infinity)
        .trainingCard()
    }

    private func start() {
        saved = false
        scene.startGame()
    }

    private func saveScore() {
        guard !saved, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        scores.save(name: name, score: scene.status.score, runID: scene.status.runID)
        saved = true
    }
}

/// SpriteKit handles drawing and touches; the independent model owns the game rules.
final class HardHatScene: SKScene {
    let status = HardHatStatus()
    private var game = HardHatGame()
    private let drone = SKNode()
    private let obstacles = SKNode()
    private var gateNodes: [Int: SKNode] = [:]
    private var previousTime: TimeInterval?

    override init() {
        super.init(size: CGSize(width: HardHatGame.width, height: HardHatGame.height))
        scaleMode = .aspectFit
        backgroundColor = UIColor(red: 0.78, green: 0.88, blue: 0.91, alpha: 1)
        buildSite()
    }

    required init?(coder: NSCoder) { nil }

    override func didMove(to view: SKView) {
        // Start when the playfield is presented, not while navigation creates the view.
        if status.phase == .ready { startGame() }
    }

    func startGame() {
        game.start()
        status.runID = UUID()
        status.score = 0
        status.phase = .playing
        obstacles.removeAllChildren()
        gateNodes.removeAll()
        previousTime = nil
        drone.position = CGPoint(x: HardHatGame.playerX, y: game.y)
    }

    func flap() { game.flap() }
    func pauseGame() {
        game.pause()
        status.phase = game.phase
        previousTime = nil
    }
    func resumeGame() {
        game.resume()
        status.phase = game.phase
        previousTime = nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { flap() }

    override func update(_ currentTime: TimeInterval) {
        defer { previousTime = currentTime }
        guard let previousTime else { return }
        game.advance(currentTime - previousTime)
        drone.position = CGPoint(x: HardHatGame.playerX, y: game.y)
        drone.zRotation = max(-0.5, min(0.35, game.velocity / 650))
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
        if status.score != game.score { status.score = game.score }
        if status.phase != game.phase { status.phase = game.phase }
    }

    private func rectangle(_ rect: CGRect, color: UIColor, parent: SKNode) {
        let node = SKShapeNode(rect: rect, cornerRadius: 2)
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
        let distant = UIColor(red: 0.45, green: 0.62, blue: 0.67, alpha: 0.35)
        for x in stride(from: 15, through: 370, by: 65) {
            let height = CGFloat(75 + (x * 7) % 105)
            rectangle(CGRect(x: CGFloat(x), y: 48, width: 45, height: height), color: distant, parent: self)
        }
        line(from: CGPoint(x: 280, y: 80), to: CGPoint(x: 280, y: 510), color: distant, width: 8, parent: self)
        line(from: CGPoint(x: 190, y: 495), to: CGPoint(x: 370, y: 495), color: distant, width: 7, parent: self)
        line(from: CGPoint(x: 210, y: 495), to: CGPoint(x: 280, y: 540), color: distant, width: 3, parent: self)
        line(from: CGPoint(x: 280, y: 540), to: CGPoint(x: 360, y: 495), color: distant, width: 3, parent: self)
        line(from: CGPoint(x: 340, y: 495), to: CGPoint(x: 340, y: 370), color: distant, width: 2, parent: self)
        addChild(obstacles)
        rectangle(CGRect(x: 0, y: 0, width: 390, height: 48),
                  color: UIColor(red: 0.22, green: 0.25, blue: 0.28, alpha: 1), parent: self)
        for x in stride(from: 0, to: 390, by: 32) {
            rectangle(CGRect(x: x, y: 38, width: 18, height: 8), color: .systemYellow, parent: self)
        }
        drone.zPosition = 10
        let helmet = SKShapeNode(ellipseOf: CGSize(width: 34, height: 28))
        helmet.fillColor = .systemYellow
        helmet.strokeColor = UIColor(red: 0.65, green: 0.35, blue: 0.04, alpha: 1)
        helmet.lineWidth = 2
        drone.addChild(helmet)
        rectangle(CGRect(x: -21, y: -10, width: 42, height: 6), color: .systemOrange, parent: drone)
        rectangle(CGRect(x: -3, y: 1, width: 6, height: 12), color: .white.withAlphaComponent(0.65), parent: drone)
        line(from: CGPoint(x: -25, y: 18), to: CGPoint(x: 25, y: 18), color: .darkGray, width: 3, parent: drone)
        line(from: CGPoint(x: 0, y: 14), to: CGPoint(x: 0, y: 20), color: .darkGray, width: 3, parent: drone)
        drone.position = CGPoint(x: HardHatGame.playerX, y: game.y)
        addChild(drone)
    }

    private func addScaffold(to parent: SKNode, bottom: Double, top: Double) {
        let steel = UIColor(red: 0.25, green: 0.31, blue: 0.35, alpha: 1)
        rectangle(CGRect(x: 0, y: bottom, width: 58, height: top - bottom),
                  color: UIColor(red: 0.94, green: 0.57, blue: 0.17, alpha: 1), parent: parent)
        for x in [5.0, 49.0] {
            rectangle(CGRect(x: x, y: bottom, width: 4, height: top - bottom), color: steel, parent: parent)
        }
        for y in stride(from: bottom + 8, to: top - 8, by: 34) {
            line(from: CGPoint(x: 9, y: y), to: CGPoint(x: 49, y: min(y + 28, top - 4)),
                 color: steel.withAlphaComponent(0.6), width: 3, parent: parent)
        }
        for y in [bottom, top - 9] {
            rectangle(CGRect(x: 0, y: y, width: 58, height: 9), color: steel, parent: parent)
            for x in stride(from: 3, to: 58, by: 16) {
                rectangle(CGRect(x: Double(x), y: y + 2, width: 8, height: 5), color: .systemYellow, parent: parent)
            }
        }
    }
}

#Preview("Hard Hat Hop") {
    NavigationStack { HardHatGameView() }
}
