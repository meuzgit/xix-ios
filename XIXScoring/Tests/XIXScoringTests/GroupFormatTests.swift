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

final class QuotaTests: XCTestCase {
    func testFixture() throws {
        try FixtureRunner.run("quota")
    }

    func testPointsTableAndPickUp() {
        XCTAssertEqual([-3, -2, -1, 0, 1, 2].map(QuotaScorer.points(strokesToPar:)), [8, 8, 4, 2, 1, 0])
        let input = RoundInput(holes: 2, par: [5, 4], strokeIndex: [],
                               players: [PlayerInput(id: "a", level: 10), PlayerInput(id: "b", level: 10)],
                               scores: [[.pickedUp, 4], [5, 4]], games: [GameInput(id: "q", format: .quota, players: ["a", "b"])])
        let r = ScoringEngine.score(input)
        guard case .quota(let d)? = r.games.first?.detail else { return XCTFail() }
        XCTAssertEqual(d.points["a"], [0, 2])
        XCTAssertEqual(d.results, ["a": -34, "b": -32])
        XCTAssertEqual(r.games[0].display["a"], "Quota -34")
    }

    func testNeedsLevelsAndPar() {
        // B.8.14 and B.8.1
        let noLevel = RoundInput(holes: 1, par: [4], strokeIndex: [],
                                 players: [PlayerInput(id: "a", level: 5), PlayerInput(id: "b")],
                                 scores: [[4], [4]], games: [GameInput(id: "q", format: .quota, players: ["a", "b"])])
        XCTAssertEqual(ScoringEngine.score(noLevel).games[0].outcome, .unavailable(reason: "Quota needs a Level for every player; missing: b"))
        let noPar = RoundInput(holes: 1, par: [nil], strokeIndex: [],
                               players: [PlayerInput(id: "a", level: 5), PlayerInput(id: "b", level: 5)],
                               scores: [[4], [4]], games: [GameInput(id: "q", format: .quota, players: ["a", "b"])])
        XCTAssertEqual(ScoringEngine.score(noPar).games[0].outcome, .unavailable(reason: "Quota needs par on every played hole; missing on 1"))
    }
}

final class RabbitTests: XCTestCase {
    func testFixture() throws {
        try FixtureRunner.run("rabbit_moves")
    }

    func testNineHoleRoundAwardsAtNineOnly() {
        // B.8.12
        var rows: [[HoleScore?]] = Array(repeating: Array(repeating: 4, count: 9), count: 2)
        rows[1][8] = 3
        let input = RoundInput(holes: 9, par: Array(repeating: 4, count: 9), strokeIndex: [],
                               players: [PlayerInput(id: "a", level: 5), PlayerInput(id: "b", level: 5)],
                               scores: rows, games: [GameInput(id: "r", format: .rabbit, players: ["a", "b"])])
        let r = ScoringEngine.score(input)
        XCTAssertEqual(r.games[0].outcome, .winner("b"))
        XCTAssertEqual(r.medals, [MedalAward(profile: "b", key: .rabbit9, opponent: "a")])
        XCTAssertEqual(r.rivalPoints, ["a": 0, "b": 10], "one award on nine holes")
        XCTAssertEqual(r.holeEvents.map(\.text), ["Rabbit to B."])
    }

    func testNeverClaimedIsVoidAndInProgressHasNoOutcome() {
        let all4: [[HoleScore?]] = Array(repeating: Array(repeating: 4, count: 9), count: 3)
        let input = RoundInput(holes: 9, par: Array(repeating: 4, count: 9), strokeIndex: [],
                               players: ["a", "b", "c"].map { PlayerInput(id: PlayerID($0), level: 5) },
                               scores: all4, games: [GameInput(id: "r", format: .rabbit, players: ["a", "b", "c"])])
        let r = ScoringEngine.score(input)
        XCTAssertEqual(r.games[0].outcome, .void)
        XCTAssertTrue(r.medals.isEmpty)
        XCTAssertEqual(r.games[0].display["a"], "Rabbit loose")
        var partial = input
        partial.scores[0][8] = nil
        XCTAssertNil(ScoringEngine.score(partial).games[0].outcome)
    }
}

final class DefenderTests: XCTestCase {
    func testFixture() throws {
        try FixtureRunner.run("defender")
    }

    func testNeedsThreePlayersAndMultiplierScalesPoints() {
        let two = RoundInput(holes: 1, par: [4], strokeIndex: [], players: [PlayerInput(id: "a"), PlayerInput(id: "b")],
                             scores: [[4], [4]], games: [GameInput(id: "d", format: .defender, players: ["a", "b"])])
        XCTAssertEqual(ScoringEngine.score(two).games[0].outcome, .unavailable(reason: "Defender needs exactly three players"))
        let callout = CalloutInput(id: "x", hole: 1, kind: .multiplier, caller: "a", targets: ["b", "c"],
                                   params: CalloutParams(game: "d", factor: 3), responses: ["b": .signed, "c": .signed])
        let input = RoundInput(holes: 2, par: [4, 4], strokeIndex: [], players: ["a", "b", "c"].map { PlayerInput(id: PlayerID($0)) },
                               scores: [[3, nil], [4, 4], [4, 4]], games: [GameInput(id: "d", format: .defender, players: ["a", "b", "c"])],
                               callouts: [callout])
        let r = ScoringEngine.score(input)
        guard case .defender(let d)? = r.games.first?.detail else { return XCTFail() }
        XCTAssertEqual(d.perHole[0].points["a"], 6)
        XCTAssertEqual(d.perHole.count, 1)
        XCTAssertNil(r.games[0].outcome)
    }
}
