import XCTest
@testable import XIXScoring

final class MedalsAndRivalPointsTests: XCTestCase {
    private func nassauInput(a: [HoleScore?], b: [HoleScore?], levels: [Double?] = [5, 5], extraGames: [GameInput] = []) -> RoundInput {
        RoundInput(holes: 18, par: Array(repeating: 4, count: 18), strokeIndex: [],
                   players: [PlayerInput(id: "a", level: levels[0]), PlayerInput(id: "b", level: levels[1])],
                   scores: [a, b],
                   games: [GameInput(id: "n", format: .nassau, players: ["a", "b"])] + extraGames)
    }

    func testNassauMedalsSkipHalvedSegmentsAndRivalPointsSplit() {
        // a wins 8–9 (front 2 up), b wins 17–18 (back 2 up), 18 halved.
        var a: [HoleScore?] = Array(repeating: 4, count: 18)
        var b: [HoleScore?] = Array(repeating: 4, count: 18)
        for h in 7..<9 { a[h] = 3 }
        for h in 16..<18 { b[h] = 3 }
        let r = ScoringEngine.score(nassauInput(a: a, b: b))
        XCTAssertEqual(r.medals, [MedalAward(profile: "a", key: .nassauFront, opponent: "b"),
                                  MedalAward(profile: "b", key: .nassauBack, opponent: "a")])
        XCTAssertEqual(r.rivalPoints, ["a": 15, "b": 15])
    }

    func testOpponentFactorUsesStrongestOpponentLevel() {
        // Same round, a is Level 3 and b Level 5: a's awards scale by 1.2, b's by 1.0.
        var a: [HoleScore?] = Array(repeating: 4, count: 18)
        var b: [HoleScore?] = Array(repeating: 4, count: 18)
        for h in 7..<9 { a[h] = 3 }
        for h in 16..<18 { b[h] = 3 }
        let r = ScoringEngine.score(nassauInput(a: a, b: b, levels: [3, 5]))
        XCTAssertEqual(r.rivalPoints, ["a": 18, "b": 15], "a: (10 + 5) × 1.2 = 18")
        XCTAssertEqual(RivalPointsBuilder.factor(for: "b", opponents: ["a"], round: NormalisedRound(nassauInput(a: a, b: b, levels: [3, 5]))), 1)
        let noLevel = ScoringEngine.score(nassauInput(a: a, b: b, levels: [nil, 5]))
        XCTAssertEqual(noLevel.rivalPoints["a"], 15, "no Level → factor 1")
    }

    func testMedalsAreIdempotentPerKeyAndOnlyOnComplete() {
        // Two Skins games both give a ≥ 2 skins → one skins_two medal.
        var a: [HoleScore?] = Array(repeating: 4, count: 18)
        let b: [HoleScore?] = Array(repeating: 4, count: 18)
        a[0] = 3; a[1] = 3
        let games = [GameInput(id: "s1", format: .skins, players: ["a", "b"]),
                     GameInput(id: "s2", format: .skins, players: ["a", "b"])]
        let r = ScoringEngine.score(nassauInput(a: a, b: b, extraGames: games))
        XCTAssertEqual(r.medals.filter { $0.key == .skinsTwo }.count, 1)
        XCTAssertEqual(r.rivalPoints["a"], 10 + 5 + 10 + 10 + 10, "front 2&1, back halved, 18 2&1, both skins games")
        var partial = nassauInput(a: a, b: b, extraGames: games)
        partial.scores[1][17] = nil
        let inProgress = ScoringEngine.score(partial)
        XCTAssertEqual(inProgress.status, .inProgress(throughHole: 17))
        XCTAssertTrue(inProgress.medals.isEmpty)
        XCTAssertTrue(inProgress.rivalPoints.isEmpty)
    }

    func testTiedOutcomesShareHalfAndNoTopMedalForMatchStyleGames() {
        // Skins tied 1–1 → 5 each; stableford tied → both get stableford_top and 5 each.
        var a: [HoleScore?] = Array(repeating: 4, count: 18)
        var b: [HoleScore?] = Array(repeating: 4, count: 18)
        a[0] = 3; b[1] = 3
        let games = [GameInput(id: "s", format: .skins, players: ["a", "b"]),
                     GameInput(id: "st", format: .stableford, players: ["a", "b"])]
        var i = nassauInput(a: a, b: b, extraGames: games)
        i.games.removeFirst()
        let r = ScoringEngine.score(i)
        XCTAssertEqual(r.games[0].outcome, .tied(["a", "b"]))
        XCTAssertEqual(r.games[1].outcome, .tied(["a", "b"]))
        XCTAssertEqual(r.rivalPoints, ["a": 10, "b": 10])
        XCTAssertEqual(r.medals.map(\.key), [.stablefordTop, .stablefordTop])
    }

    func testPersonalBestMedal() {
        var i = nassauInput(a: Array(repeating: 4, count: 18), b: Array(repeating: 4, count: 18))
        i.games = []
        i.players[0].extras = PlayerExtras(personalBest: 75)
        i.players[1].extras = PlayerExtras(personalBest: 72)
        let r = ScoringEngine.score(i)
        XCTAssertEqual(r.medals, [MedalAward(profile: "a", key: .personalBest)])
    }

    func testBaseByFormatClass() {
        XCTAssertEqual(RivalPointsBuilder.base(for: .skins, teamed: false), 10)
        XCTAssertEqual(RivalPointsBuilder.base(for: .matchPlay, teamed: false), 10)
        XCTAssertEqual(RivalPointsBuilder.base(for: .matchPlay, teamed: true), 6)
        XCTAssertEqual(RivalPointsBuilder.base(for: .vegas, teamed: true), 6)
        XCTAssertEqual(RivalPointsBuilder.base(for: .mostPars, teamed: false), 4)
        XCTAssertEqual(RivalPointsBuilder.calloutBase, 3)
    }

    func testStablefordAndBirdiesLeaderboards() {
        var a: [HoleScore?] = Array(repeating: 4, count: 18); a[0] = 3
        let b: [HoleScore?] = Array(repeating: 4, count: 18)
        var i = nassauInput(a: a, b: b, extraGames: [GameInput(id: "st", format: .stableford, players: ["a", "b"])])
        i.games.removeFirst()
        let r = ScoringEngine.score(i)
        XCTAssertEqual(r.leaderboard[.stableford]?.map { ($0.player, $0.value) }.map { "\($0.0):\($0.1)" }, ["a:37", "b:36"])
        XCTAssertEqual(r.leaderboard[.birdies]?.map { "\($0.player):\($0.value)" }, ["a:1", "b:0"])
    }
}

final class MedalTieRuleTests: XCTestCase {
    /// Top/low style keys are shared by every tied player; match-style keys never award on a halve.
    func testTopStyleKeysShareOnTiesAndMatchStyleKeysNeverAwardOnHalves() {
        let scores: [[HoleScore?]] = [[4, 4, 4], [4, 4, 4]]
        let input = RoundInput(holes: 3, par: [4, 4, 4], strokeIndex: [],
                               players: [PlayerInput(id: "a", level: 5), PlayerInput(id: "b", level: 5)],
                               scores: scores,
                               games: [GameInput(id: "st", format: .stableford, players: ["a", "b"]),
                                       GameInput(id: "m", format: .matchPlay, players: ["a", "b"])])
        let r = ScoringEngine.score(input)
        XCTAssertEqual(r.games[0].outcome, .tied(["a", "b"]))
        XCTAssertEqual(r.games[1].outcome, .halved)
        XCTAssertEqual(r.medals, [MedalAward(profile: "a", key: .stablefordTop, opponent: "b"),
                                  MedalAward(profile: "b", key: .stablefordTop, opponent: "a")])
        XCTAssertFalse(r.medals.contains { $0.key == .matchplayWin })
        XCTAssertEqual(r.rivalPoints, ["a": 10, "b": 10], "half of 10 from each game")
    }
}
