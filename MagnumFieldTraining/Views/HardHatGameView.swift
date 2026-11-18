import SwiftUI
import SpriteKit
import Observation

@MainActor
@Observable
final class HardHatStatus {
    var phase: HardHatGame.Phase = .ready
    var score = 0
    var runID = UUID()
    var newBest = false
    var celebration = 0
}

struct HardHatGameView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("HardHatHop.sound") private var sound = true
    @AppStorage("HardHatHop.haptics") private var haptics = true
    @State private var scene = HardHatScene()
    @State private var scores = HardHatScores()
    @State private var name = ""
    @State private var saved = false
    @State private var showingScores = false
    @State private var latestSavedID: UUID?

    var body: some View {
        VStack(spacing: 12) {
            HardHatScoreBar(score: scene.status.score, best: max(scores.best, scene.status.score),
                            newBest: scene.status.newBest)
            GeometryReader { geometry in
                HardHatRenderView(scene: scene, isPaused: scene.status.phase == .paused || scene.status.phase == .ended || scenePhase != .active)
                    .aspectRatio(390.0 / 640.0, contentMode: .fit)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .accessibilityLabel("Hard Hat Hop play area")
                    .accessibilityHint("Double tap to boost the drone.")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { scene.flap() }
            }
            .background(AppStyle.charcoal)
            .overlay(alignment: .top) {
                HardHatCelebration(status: scene.status)
                    .allowsHitTesting(false)
            }
            .overlay {
                if scene.status.phase == .paused || scene.status.phase == .ended {
                    ScrollView {
                        HardHatGameMenu(phase: scene.status.phase, score: scene.status.score,
                                        newBest: scene.status.newBest, name: $name, saved: saved,
                                        resume: scene.resumeGame, restart: start, save: saveScore)
                            .padding(20)
                            .frame(maxWidth: 380)
                            .frame(maxWidth: .infinity)
                    }
                    .defaultScrollAnchor(.center)
                    .background(AppStyle.charcoal.opacity(0.40))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(AppStyle.brand.opacity(0.25)) }

            HardHatControls(sound: $sound, haptics: $haptics)
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
            HardHatLeaderboard(scores: scores, latestID: latestSavedID)
        }
        .onAppear { configure() }
        .onChange(of: sound) { _, _ in configure() }
        .onChange(of: haptics) { _, _ in configure() }
        .onChange(of: reduceMotion) { _, _ in configure() }
        .onChange(of: scene.status.phase) { _, phase in
            if phase == .ended { scores.recordBest(scene.status.score) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { scene.pauseGame() }
        }
        .onDisappear {
            scene.pauseGame()
            scene.feedback.stop()
        }
    }

    private func configure() {
        scene.configure(sound: sound, haptics: haptics, reduceMotion: reduceMotion, best: scores.best)
    }

    private func start() {
        saved = false
        scene.recordToBeat = scores.best
        scene.startGame()
    }

    private func saveScore() {
        guard !saved, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        scores.save(name: name, score: scene.status.score, runID: scene.status.runID)
        latestSavedID = scene.status.runID
        saved = true
    }
}

/// Keep the renderer's pause state synchronized on every SwiftUI update,
/// including a restart that reuses the existing scene.
private struct HardHatRenderView: UIViewRepresentable {
    let scene: HardHatScene
    let isPaused: Bool

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.presentScene(scene)
        view.isPaused = isPaused
        scene.isPaused = isPaused
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
        scene.isPaused = isPaused
        view.isPaused = isPaused
    }

    static func dismantleUIView(_ view: SKView, coordinator: ()) {
        view.isPaused = true
        view.presentScene(nil)
    }
}

private struct HardHatScoreBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let score: Int
    let best: Int
    let newBest: Bool

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Label("Score", systemImage: "flag.checkered")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Text(score, format: .number)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: score)
                    .keyframeAnimator(initialValue: CGFloat(1), trigger: score) { [reduceMotion] content, scale in
                        content.scaleEffect(reduceMotion ? 1 : scale)
                    } keyframes: { _ in
                        LinearKeyframe(1.12, duration: 0.1)
                        SpringKeyframe(1, duration: 0.2)
                    }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                Label(newBest ? "New Best!" : "Personal Best", systemImage: "trophy.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 1, green: 0.83, blue: 0.42))
                Text(best, format: .number)
                    .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(LinearGradient(colors: [AppStyle.brand, AppStyle.brand.opacity(0.86)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

private struct HardHatControls: View {
    @Binding var sound: Bool
    @Binding var haptics: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Toggle(isOn: $sound) {
                    Label("Sound", systemImage: sound ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
                Toggle(isOn: $haptics) {
                    Label("Haptics", systemImage: "hand.tap.fill")
                }
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .tint(AppStyle.accent)
            .font(.subheadline)
            Text("Tap to fly. Dodge the scaffolding.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct HardHatCelebration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let status: HardHatStatus
    @State private var visible = false

    var body: some View {
        Group {
            if visible && status.phase == .playing {
                Label(status.newBest ? "New Best!" : "Keep Flying!", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(AppStyle.brand, in: Capsule())
                    .padding(12)
                    .transition(.opacity)
            }
        }
        .task(id: status.celebration) {
            guard status.celebration > 0 else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { visible = true }
            do { try await Task.sleep(for: .seconds(1.4)) } catch { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { visible = false }
        }
    }
}

private struct HardHatGameMenu: View {
    let phase: HardHatGame.Phase
    let score: Int
    let newBest: Bool
    @Binding var name: String
    let saved: Bool
    let resume: () -> Void
    let restart: () -> Void
    let save: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: phase == .paused ? "pause.circle.fill" : (newBest ? "trophy.fill" : "cone.fill"))
                .font(.system(size: 42))
                .foregroundStyle(AppStyle.accent)
                .accessibilityHidden(true)
            Text(phase == .paused ? "On Break" : "Site Closed!")
                .font(.system(.title, design: .rounded, weight: .bold))
            if phase == .paused {
                Text("Ready for another lift?")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Resume", systemImage: "play.fill", action: resume)
                    .buttonStyle(.borderedProminent)
            } else {
                VStack(spacing: 4) {
                    Text(score, format: .number)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit())
                    Text(newBest ? "New Personal Best" : "Final Score")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                Button("Try Again", systemImage: "arrow.clockwise", action: restart)
                    .buttonStyle(.borderedProminent)
                Divider()
                TextField("Your name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .disabled(saved)
                    .onChange(of: name) { _, value in name = String(value.prefix(24)) }
                    .onSubmit(save)
                Button(saved ? "Score Saved" : "Save Score", systemImage: saved ? "checkmark.circle.fill" : "trophy", action: save)
                    .buttonStyle(.bordered)
                    .disabled(saved || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .controlSize(.large)
        .tint(AppStyle.accent)
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(AppStyle.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(AppStyle.brand.opacity(0.18)) }
        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
    }
}

private struct HardHatLeaderboard: View {
    @Environment(\.dismiss) private var dismiss
    let scores: HardHatScores
    let latestID: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HardHatScoreBar(score: scores.best, best: scores.best, newBest: false)
                    ForEach(Array(scores.entries.enumerated()), id: \.element.id) { index, entry in
                        HardHatLeaderboardRow(entry: entry, rank: index + 1, latest: entry.id == latestID)
                    }
                    if scores.entries.isEmpty {
                        ContentUnavailableView("Your spot is waiting", systemImage: "trophy",
                            description: Text("Finish a run and save your name to join the leaderboard."))
                    }
                    Text("Top 10 scores on this device. Your best score is saved automatically.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .background(AppStyle.background)
            .navigationTitle("Site Legends")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

private struct HardHatLeaderboardRow: View {
    let entry: HardHatScores.Entry
    let rank: Int
    let latest: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(rank <= 3 ? AppStyle.brand : Color.secondary.opacity(0.12))
                if rank <= 3 {
                    Image(systemName: "medal.fill")
                        .foregroundStyle(rank == 1 ? Color.yellow : (rank == 2 ? Color.white : Color.orange))
                }
                Text(rank, format: .number)
                    .font(.caption2.bold())
                    .foregroundStyle(rank <= 3 ? .white : .primary)
                    .offset(y: rank <= 3 ? 15 : 0)
            }
            .frame(width: 46, height: 46)
            .accessibilityLabel("Rank: \(rank)")
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name).font(.headline)
                Text(entry.date, format: .dateTime.month().day().year())
                    .font(.caption).foregroundStyle(.secondary)
                if latest {
                    Text("Latest Entry").font(.caption.weight(.semibold)).foregroundStyle(AppStyle.accent)
                }
            }
            Spacer(minLength: 4)
            Text(entry.score, format: .number)
                .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
        }
        .padding(16)
        .background(AppStyle.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(latest ? AppStyle.accent : AppStyle.border, lineWidth: latest ? 2 : 1) }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Hard Hat Hop") {
    NavigationStack { HardHatGameView() }
}
