import XCTest
@testable import XIXScoring

final class NinesTests: XCTestCase {
    func testFixture() throws {
        try FixtureRunner.run("nines_ties")
    }

    func testAllocation() {
        XCTAssertEqual(NinesScorer.allocate([4, 3, 5]), [3, 5, 1])
        XCTAssertEqual(NinesScorer.allocate([4, 4, 5]), [4, 4, 1])
        XCTAssertEqual(NinesScorer.allocate([5, 3, 5]), [2, 5, 2])
        XCTAssertEqual(NinesScorer.allocate([4, 4, 4]), [3, 3, 3])
    }

    func testNeedsExactlyThreePlayers() {
        // B.8.13
        let two = RoundInput(holes: 1, par: [4], strokeIndex: [], players: [PlayerInput(id: "a"), PlayerInput(id: "b")],
                             scores: [[4], [4]], games: [GameInput(id: "n", format: .nines, players: ["a", "b"])])
        XCTAssertEqual(ScoringEngine.score(two).games[0].outcome, .unavailable(reason: "Nines needs exactly three players"))
        let four = RoundInput(holes: 1, par: [4], strokeIndex: [], players: ["a", "b", "c", "d"].map { PlayerInput(id: PlayerID($0)) },
                              scores: [[4], [4], [4], [4]], games: [GameInput(id: "n", format: .nines, players: ["a", "b", "c", "d"])])
        XCTAssertTrue(ScoringEngine.score(four).games[0].outcome?.isUnavailable ?? false)
    }
}

final class SixesTests: XCTestCase {
    func testFixture() throws {
        try FixtureRunner.run("sixes_rotation")
    }

    func testNeedsEighteenHolesAndFourPlayers() {
        // B.8.12, B.8.13
        let nine = RoundInput(holes: 9, par: Array(repeating: 4, count: 9), strokeIndex: [],
                              players: ["a", "b", "c", "d"].map { PlayerInput(id: PlayerID($0)) },
                              scores: [[], [], [], []], games: [GameInput(id: "s", format: .sixes, players: ["a", "b", "c", "d"])])
        XCTAssertEqual(ScoringEngine.score(nine).games[0].outcome, .unavailable(reason: "Sixes needs an 18-hole round"))
        let three = RoundInput(holes: 18, par: Array(repeating: 4, count: 18), strokeIndex: [],
                               players: ["a", "b", "c"].map { PlayerInput(id: PlayerID($0)) },
                               scores: [[], [], []], games: [GameInput(id: "s", format: .sixes, players: ["a", "b", "c"])])
        XCTAssertEqual(ScoringEngine.score(three).games[0].outcome, .unavailable(reason: "Sixes needs exactly four players"))
    }

    func testInProgressSegmentsAndTiedOutcome() {
        var rows: [[HoleScore?]] = Array(repeating: Array(repeating: 4, count: 18), count: 4)
        rows[0][0] = 3          // AB win segment 1 1 up
        rows[3][12] = 3         // AD win segment 3 1 up
        let input = RoundInput(holes: 18, par: Array(repeating: 4, count: 18), strokeIndex: [],
                               players: ["a", "b", "c", "d"].map { PlayerInput(id: PlayerID($0), level: 5) },
                               scores: rows, games: [GameInput(id: "s", format: .sixes, players: ["a", "b", "c", "d"])])
        let r = ScoringEngine.score(input)
        guard case .sixes(let d)? = r.games.first?.detail else { return XCTFail() }
        XCTAssertEqual(d.totals, ["a": 5, "b": 3, "c": 1, "d": 3])
        XCTAssertEqual(r.games[0].outcome, .winner("a"))
        var partial = input
        partial.scores[2][17] = nil
        let p = ScoringEngine.score(partial)
        XCTAssertNil(p.games[0].outcome)
        if case .sixes(let pd)? = p.games.first?.detail { XCTAssertFalse(pd.segments[2].match.complete) } else { XCTFail() }
    }
}
