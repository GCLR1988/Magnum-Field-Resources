import AVFAudio
import UIKit

/// Short synthesized cues need no downloaded assets and respect the device's silent switch.
@MainActor
final class HardHatFeedback {
    enum Cue: CaseIterable {
        case boost, score, impact
    }

    private var players: [Cue: AVAudioPlayer] = [:]
    private var soundEnabled = false
    private var hapticsEnabled = false
    private var sessionActive = false
    private let boostHaptic = UIImpactFeedbackGenerator(style: .soft)
    private let scoreHaptic = UISelectionFeedbackGenerator()
    private let impactHaptic = UINotificationFeedbackGenerator()

    func configure(sound: Bool, haptics: Bool) {
        soundEnabled = sound
        hapticsEnabled = haptics
        if sound {
            prepareAudio()
        } else {
            stopAudio()
        }
        if haptics { boostHaptic.prepare() }
    }

    func play(_ cue: Cue) {
        if soundEnabled {
            if !sessionActive { prepareAudio() }
            if let player = players[cue] {
                player.currentTime = 0
                player.play()
            }
        }
        guard hapticsEnabled else { return }
        switch cue {
        case .boost: boostHaptic.impactOccurred(intensity: 0.35)
        case .score: scoreHaptic.selectionChanged()
        case .impact: impactHaptic.notificationOccurred(.warning)
        }
    }

    func pause() {
        for player in players.values { player.stop() }
    }

    func stop() { stopAudio() }

    private func prepareAudio() {
        guard !sessionActive else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
            if players.isEmpty {
                for cue in Cue.allCases {
                    let player = try AVAudioPlayer(data: Self.wave(for: cue))
                    player.volume = cue == .boost ? 0.18 : 0.28
                    player.prepareToPlay()
                    players[cue] = player
                }
            }
            sessionActive = true
        } catch {
            // Audio is optional; an unavailable route must never interrupt the game.
            pause()
            sessionActive = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func stopAudio() {
        pause()
        guard sessionActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionActive = false
    }

    private static func wave(for cue: Cue) -> Data {
        let rate = 22_050
        let duration: Double = cue == .boost ? 0.09 : (cue == .score ? 0.22 : 0.18)
        let count = Int(Double(rate) * duration)
        var samples = Data(capacity: count * 2)
        var phase = 0.0
        for index in 0..<count {
            let t = Double(index) / Double(rate)
            let progress = t / duration
            let frequency: Double
            switch cue {
            case .boost: frequency = 280 + progress * 260
            case .score: frequency = progress < 0.48 ? 660 : 880
            case .impact: frequency = 150 - progress * 90
            }
            phase += 2 * .pi * frequency / Double(rate)
            let attack = min(1, t / 0.008)
            let release = min(1, (duration - t) / 0.035)
            let envelope = attack * release * (1 - progress * 0.35)
            let value = Int16(sin(phase) * envelope * 15_000)
            append(value, to: &samples)
        }
        var result = Data("RIFF".utf8)
        append(UInt32(36 + samples.count), to: &result)
        result.append(Data("WAVEfmt ".utf8))
        append(UInt32(16), to: &result)
        append(UInt16(1), to: &result) // PCM
        append(UInt16(1), to: &result) // mono
        append(UInt32(rate), to: &result)
        append(UInt32(rate * 2), to: &result)
        append(UInt16(2), to: &result)
        append(UInt16(16), to: &result)
        result.append(Data("data".utf8))
        append(UInt32(samples.count), to: &result)
        result.append(samples)
        return result
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
