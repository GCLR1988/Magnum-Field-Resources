import Foundation
import Testing
@testable import HardHatHop

@Test func idlePauseAndRestart() {
    var game = HardHatGame()
    game.advance(1)
    #expect(game.y == 340)
    game.start()
    game.advance(1.0 / 60, nextCenter: { 340 })
    #expect(game.y > 340)
    game.pause()
    let y = game.y
    game.flap()
    game.advance(1)
    #expect(game.y == y)
    game.resume()
    #expect(game.phase == .playing)
    game.start()
    #expect(game.score == 0 && game.gates.isEmpty)
}

@Test func collisionsEndRunAndStopMovement() {
    var game = HardHatGame()
    game.start()
    for _ in 0..<300 { game.advance(1.0 / 60, nextCenter: { 340 }) }
    #expect(game.phase == .ended)
    let y = game.y
    game.flap()
    game.advance(1)
    #expect(game.y == y)
}

@Test func passingGatesScoresOnceAndCleansOldObstacles() {
    var game = HardHatGame()
    game.start()
    for _ in 0..<1200 {
        if game.y < 330 && game.velocity < 0 { game.flap() }
        game.advance(1.0 / 60, nextCenter: { 360 })
    }
    #expect(game.phase == .playing)
    #expect(game.score > 5)
    #expect(game.gates.count <= 3)
    #expect(Set(game.gates.map(\.id)).count == game.gates.count)
}

@Test func frameStallsAreClamped() {
    var game = HardHatGame()
    game.start()
    game.advance(30, nextCenter: { 340 })
    #expect(game.phase == .playing)
    #expect(game.y < 355)
}

@Test @MainActor func scoresSurviveRelaunchAndKeepTopTen() throws {
    let suite = "HardHatTests." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let scores = HardHatScores(defaults: defaults)
    let runID = UUID()
    scores.save(name: "  Builder  ", score: 15, runID: runID)
    scores.save(name: "Duplicate", score: 15, runID: runID)
    #expect(scores.entries.count == 1)
    #expect(scores.entries.first?.name == "Builder")
    scores.save(name: " ", score: 30, runID: UUID())
    #expect(scores.entries.count == 1)
    for score in 0..<20 { scores.save(name: "Operator", score: score, runID: UUID()) }
    scores.recordBest(25)
    let restored = HardHatScores(defaults: defaults)
    #expect(restored.entries.count == 10)
    #expect(restored.entries.first?.score == 19)
    #expect(restored.best == 25)
}
