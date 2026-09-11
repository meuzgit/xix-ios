import XCTest
@testable import XIXScoring

final class SideFormatTests: XCTestCase {
    func testBestBallFixture() throws {
        try FixtureRunner.run("best_ball")
    }

    func testBestBallMatchWaitsForEveryMemberOfASide() {
        // Hole 1: b has not entered → unresolved, even though a's 3 would win the side.
        let input = RoundInput(holes: 2, par: [4, 4], strokeIndex: [],
                               players: ["a", "b", "c", "d"].map { PlayerInput(id: PlayerID($0), level: 5) },
                               scores: [[3, nil], [nil, nil], [4, nil], [4, nil]],
                               games: [GameInput(id: "g", format: .bestBall, players: ["a", "b", "c", "d"],
                                                 sides: ["a": 0, "b": 0, "c": 1, "d": 1])])
        let r = ScoringEngine.score(input)
        if case .matchPlay(let m)? = r.games.first?.detail {
            XCTAssertEqual(m.throughHole, 0)
            XCTAssertEqual(m.result, "all square")
        } else { XCTFail() }
        XCTAssertEqual(r.games[0].display["a"], "Best Ball to play")
    }

    func testBestBallNeedsTwoSidesAndDefaultsToMatch() {
        let three = RoundInput(holes: 1, par: [4], strokeIndex: [],
                               players: ["a", "b", "c"].map { PlayerInput(id: PlayerID($0), level: 5) },
                               scores: [[4], [4], [4]],
                               games: [GameInput(id: "g", format: .bestBall, players: ["a", "b", "c"], sides: ["a": 0, "b": 1, "c": 2])])
        XCTAssertEqual(ScoringEngine.score(three).games[0].outcome, .unavailable(reason: "best_ball needs exactly two sides (0 and 1)"))
        let two = RoundInput(holes: 1, par: [4], strokeIndex: [],
                             players: ["a", "b"].map { PlayerInput(id: PlayerID($0), level: 5) },
                             scores: [[3], [4]],
                             games: [GameInput(id: "g", format: .bestBall, players: ["a", "b"])])
        let r = ScoringEngine.score(two)
        XCTAssertEqual(r.games[0].outcome, .winner("a"))
        XCTAssertEqual(r.games[0].display["a"], "Best Ball 1 up")
    }
}
