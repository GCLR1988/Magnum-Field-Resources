import Foundation
import Observation

@MainActor
@Observable
final class HardHatScores {
    struct Entry: Identifiable, Codable {
        let id: UUID
        let name: String
        let score: Int
        let date: Date
    }

    private(set) var entries: [Entry]
    private(set) var best: Int
    private let defaults: UserDefaults
    private let entriesKey = "HardHatHop.scores.v1"
    private let bestKey = "HardHatHop.best.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded = defaults.data(forKey: entriesKey)
            .flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        entries = Array(decoded.filter { $0.score >= 0 }.sorted { $0.score > $1.score }.prefix(10))
        best = max(defaults.integer(forKey: bestKey), decoded.map(\.score).max() ?? 0)
    }

    func recordBest(_ score: Int) {
        guard score > best else { return }
        best = score
        defaults.set(best, forKey: bestKey)
    }

    func save(name: String, score: Int, runID: UUID) {
        guard score >= 0, !entries.contains(where: { $0.id == runID }) else { return }
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        guard !trimmed.isEmpty else { return }
        entries.append(Entry(id: runID, name: trimmed, score: score, date: Date()))
        entries.sort { $0.score == $1.score ? $0.date > $1.date : $0.score > $1.score }
        entries = Array(entries.prefix(10))
        recordBest(score)
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: entriesKey)
        }
    }
}
