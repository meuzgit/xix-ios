import XCTest
@testable import XIXScoring

final class MatchPlayTests: XCTestCase {
    private func input(holes: Int = 18, format: Format = .matchPlay, players: [String] = ["a", "b"],
                       scores: [[HoleScore?]], options: Options = Options(), sides: [PlayerID: Int]? = nil,
                       levels: [Double?]? = nil, callouts: [CalloutInput] = []) -> RoundInput {
        RoundInput(holes: holes, par: Array(repeating: 4, count: holes), strokeIndex: [],
                   players: players.enumerated().map { i, id in
                       let level: Double? = levels == nil ? 5 : levels![i]
                       return PlayerInput(id: PlayerID(id), level: level)
                   },
                   scores: scores,
                   games: [GameInput(id: "m", format: format, options: options, players: players.map { PlayerID($0) }, sides: sides)],
                   callouts: callouts)
    }

    private func match(_ r: RoundResult) -> MatchPlayDetail? {
        if case .matchPlay(let d)? = r.games.first?.detail { return d }
        return nil
    }

    private func nassau(_ r: RoundResult) -> NassauDetail? {
        if case .nassau(let d)? = r.games.first?.detail { return d }
        return nil
    }

    /// a wins holes 1–4, then all halved: 4 up with 4 to play after 14 → 4&3 at hole 15.
    private var decided4and3: [[HoleScore?]] {
        let a: [HoleScore?] = [3, 3, 3, 3] + Array(repeating: 4, count: 14)
        let b: [HoleScore?] = Array(repeating: 4, count: 18)
        return [a, b]
    }

    func testDecidedEarlyFreezesStandings() {
        // B.8.6: a leads 4 up after 15 with 3 to play; b then wins 16–18 but the result stands.
        var scores = decided4and3
        scores[1][15] = 3; scores[1][16] = 3; scores[1][17] = 3
        let r = ScoringEngine.score(input(scores: scores))
        let m = match(r)!
        XCTAssertEqual(m.decidedAtHole, 15)
        XCTAssertEqual(m.result, "a 4&3")
        XCTAssertEqual(m.holesWon, ["a": 4, "b": 0])
        XCTAssertEqual(m.halved, 11)
        XCTAssertEqual(m.throughHole, 15)
        XCTAssertEqual(m.holesRemaining, 0)
        XCTAssertEqual(m.perHole.count, 15)
        XCTAssertEqual(r.games[0].outcome, .winner("a"))
        XCTAssertEqual(r.games[0].display["a"], "Match won 4&3")
        XCTAssertEqual(r.games[0].display["b"], "Match lost 4&3")
        XCTAssertEqual(r.games[0].standings.map(\.rank), [1, 2])
    }

    func testLeadEqualToRemainingIsNotDecided() {
        // 4 up with 4 to play after hole 14 (dormie): not decided yet.
        var scores = decided4and3
        scores[0] = Array(scores[0].prefix(14)) + Array(repeating: nil, count: 4)
        scores[1] = Array(scores[1].prefix(14)) + Array(repeating: nil, count: 4)
        let m = match(ScoringEngine.score(input(scores: scores)))!
        XCTAssertNil(m.decidedAtHole)
        XCTAssertFalse(m.complete)
        XCTAssertEqual(m.result, "a 4 up")
        XCTAssertEqual(m.holesRemaining, 4)
    }

    func testWonOnLastHoleReadsOneUpAndHalvedMatch() {
        var a: [HoleScore?] = Array(repeating: 4, count: 18); a[17] = 3
        let b: [HoleScore?] = Array(repeating: 4, count: 18)
        let won = match(ScoringEngine.score(input(scores: [a, b])))!
        XCTAssertEqual(won.result, "a 1 up")
        XCTAssertNil(won.decidedAtHole)
        XCTAssertTrue(won.complete)
        let halved = ScoringEngine.score(input(scores: [b, b]))
        XCTAssertEqual(match(halved)!.result, "halved")
        XCTAssertEqual(halved.games[0].outcome, .halved)
        XCTAssertEqual(halved.games[0].display["a"], "Match halved")
        XCTAssertEqual(halved.games[0].standings.map(\.rank), [1, 1])
    }

    func testInProgressAllSquareAndDown() {
        var a: [HoleScore?] = Array(repeating: nil, count: 18); a[0] = 4; a[1] = 5
        var b: [HoleScore?] = Array(repeating: nil, count: 18); b[0] = 4; b[1] = 4
        let r = ScoringEngine.score(input(scores: [a, b]))
        XCTAssertEqual(match(r)!.result, "b 1 up")
        XCTAssertEqual(r.games[0].display["a"], "Match 1 down")
        XCTAssertNil(r.games[0].outcome)
        let square = ScoringEngine.score(input(scores: [a, a]))
        XCTAssertEqual(match(square)!.result, "all square")
        XCTAssertEqual(square.games[0].display["a"], "Match all square")
    }

    func testBestBallTeamsViaSides() {
        // Side 0 = a+b, side 1 = c+d. Side 0's best ball wins hole 1 through b; hole 2 halved.
        var rows: [[HoleScore?]] = Array(repeating: Array(repeating: nil, count: 18), count: 4)
        rows[0][0] = 5; rows[1][0] = 3; rows[2][0] = 4; rows[3][0] = 4
        rows[0][1] = 4; rows[1][1] = 5; rows[2][1] = 4; rows[3][1] = 6
        let r = ScoringEngine.score(input(players: ["a", "b", "c", "d"], scores: rows,
                                          sides: ["a": 0, "b": 0, "c": 1, "d": 1]))
        let m = match(r)!
        XCTAssertEqual(m.holesWon, ["a+b": 1, "c+d": 0])
        XCTAssertEqual(m.halved, 1)
        XCTAssertEqual(m.result, "a+b 1 up")
        XCTAssertEqual(r.games[0].display["d"], "Match 1 down")
    }

    func testMultiplierHoleCountsAsFactorHolesUp() {
        // a wins the doubled hole 1 (2 up), b wins hole 2, the rest halved → a 1 up.
        let callout = CalloutInput(id: "x", hole: 1, kind: .multiplier, caller: "a", targets: ["b"],
                                   params: CalloutParams(game: "m", factor: 2), responses: ["b": .signed])
        var a: [HoleScore?] = Array(repeating: 4, count: 18); a[0] = 3
        var b: [HoleScore?] = Array(repeating: 4, count: 18); b[1] = 3
        let m = match(ScoringEngine.score(input(scores: [a, b], callouts: [callout])))!
        XCTAssertEqual(m.holesWon, ["a": 2, "b": 1])
        XCTAssertEqual(m.perHole[0].worth, 2)
        XCTAssertEqual(m.result, "a 1 up")
        XCTAssertNil(m.decidedAtHole)
    }

    func testUnavailableConfigurations() {
        let three = ScoringEngine.score(input(players: ["a", "b", "c"], scores: [[], [], []]))
        XCTAssertEqual(three.games[0].outcome, .unavailable(reason: "match_play needs two players, or teams via sides"))
        let net = ScoringEngine.score(input(scores: [[], []], options: Options(net: true), levels: [5, nil]))
        guard case .unavailable(let reason)? = net.games[0].outcome else { return XCTFail("expected unavailable") }
        XCTAssertTrue(reason.contains("Level"), reason)
    }

    func testNetMatchPlayUsesNetStrokes() {
        // a: Level 1 → 22 strokes, evenly over 18 → 4 holes get 2, 14 get 1. b: Level 10 → 0.
        let a: [HoleScore?] = Array(repeating: 5, count: 18)
        let b: [HoleScore?] = Array(repeating: 4, count: 18)
        // a nets 3 on holes 1–4 and wins them, then every hole halves: 4 up with 3 to play at 15 → 4&3.
        let m = match(ScoringEngine.score(input(scores: [a, b], options: Options(net: true), levels: [1, 10])))!
        XCTAssertEqual(m.holesWon["a"], 4)
        XCTAssertEqual(m.halved, 11)
        XCTAssertEqual(m.decidedAtHole, 15)
        XCTAssertEqual(m.result, "a 4&3")
    }

    // MARK: Nassau

    func testNassauEighteenHalvedWhileFrontAndBackSplit() {
        // B.8.7: a wins 8–9 (front 2 up), b wins 17–18 (back 2 up), everything else halved → 18 halved.
        // Winning the last two holes is the only way to finish a nine "2 up" without an early decision.
        var a: [HoleScore?] = Array(repeating: 4, count: 18)
        var b: [HoleScore?] = Array(repeating: 4, count: 18)
        for h in 7..<9 { a[h] = 3 }
        for h in 16..<18 { b[h] = 3 }
        let r = ScoringEngine.score(input(format: .nassau, scores: [a, b]))
        let n = nassau(r)!
        XCTAssertEqual(n.front.result, "a 2 up")
        XCTAssertEqual(n.back.result, "b 2 up")
        XCTAssertEqual(n.match18.result, "halved")
        XCTAssertNil(n.front.decidedAtHole)
        XCTAssertNil(n.back.decidedAtHole)
        XCTAssertEqual(n.front.matchOutcome, .winner("a"))
        XCTAssertEqual(n.back.matchOutcome, .winner("b"))
        XCTAssertEqual(n.match18.matchOutcome, .halved)
        XCTAssertEqual(r.games[0].outcome, .halved)
        XCTAssertEqual(r.games[0].display["a"], "Nassau 2 up front · 2 down back · 18 halved")
        XCTAssertEqual(r.games[0].standings.map(\.rank), [1, 1])
    }

    func testNassauSegmentsResolveIndependentlyInProgress() {
        var a: [HoleScore?] = Array(repeating: nil, count: 18)
        var b: [HoleScore?] = Array(repeating: nil, count: 18)
        for h in 0..<11 { a[h] = 4; b[h] = 4 }
        a[10] = 3
        let r = ScoringEngine.score(input(format: .nassau, scores: [a, b]))
        let n = nassau(r)!
        XCTAssertEqual(n.front.result, "halved")
        XCTAssertEqual(n.back.result, "a 1 up")
        XCTAssertEqual(n.back.throughHole, 11)
        XCTAssertFalse(n.back.complete)
        XCTAssertEqual(n.match18.result, "a 1 up")
        XCTAssertNil(r.games[0].outcome)
        XCTAssertEqual(r.games[0].display["b"], "Nassau front halved · 1 down back · 1 down 18")
    }

    func testNassauSegmentBeforeItStartsReadsToPlay() {
        var a: [HoleScore?] = Array(repeating: nil, count: 18); a[0] = 3
        var b: [HoleScore?] = Array(repeating: nil, count: 18); b[0] = 4
        let r = ScoringEngine.score(input(format: .nassau, scores: [a, b]))
        XCTAssertEqual(r.games[0].display["a"], "Nassau 1 up front · back to play · 1 up 18")
    }

    func testNassauUnavailableOnNineHolesAndWithPresses() {
        // B.8.12
        let nine = ScoringEngine.score(input(holes: 9, format: .nassau, scores: [[], []]))
        XCTAssertEqual(nine.games[0].outcome, .unavailable(reason: "Nassau needs an 18-hole round"))
        let presses = ScoringEngine.score(input(format: .nassau, scores: [[], []], options: Options(presses: true)))
        XCTAssertEqual(presses.games[0].outcome, .unavailable(reason: "presses are not supported"))
    }
}

final class MatchDepartureTests: XCTestCase {
    /// B.8.2 interaction: a side whose member left the round resolves on its remaining members.
    func testSideWithDepartedMemberResolvesOnRemainingMembers() {
        var players = ["a", "b", "c", "d"].map { PlayerInput(id: PlayerID($0), level: 5) }
        players[1].extras = PlayerExtras(leftAfterHole: 1)
        let input = RoundInput(holes: 3, par: [4, 4, 4], strokeIndex: [], players: players,
                               scores: [[4, 3, 4], [4, nil, nil], [4, 4, 4], [4, 4, 3]],
                               games: [GameInput(id: "g", format: .bestBall, players: ["a", "b", "c", "d"],
                                                 sides: ["a": 0, "b": 0, "c": 1, "d": 1])])
        let r = ScoringEngine.score(input)
        XCTAssertEqual(r.status, .complete, "b's missing holes after leaving are not awaited")
        guard case .matchPlay(let m)? = r.games.first?.detail else { return XCTFail() }
        XCTAssertEqual(m.throughHole, 3)
        XCTAssertEqual(m.perHole.map(\.winner), [nil, "a+b", "c+d"])
        XCTAssertEqual(m.result, "halved")
    }
}

final class CompactDisplayTests: XCTestCase {
    func testCompactStandingsForNassauAndMatchPlay() {
        // Fraserview: front 2&1 to Ray, back halved, 18 5&4 to Ray.
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/fraserview_2026-09-09.json")
        struct Envelope: Decodable { let input: RoundInput }
        let input = try! JSONDecoder().decode(Envelope.self, from: try! Data(contentsOf: url)).input
        let r = ScoringEngine.score(input)
        let nassau = r.games.first { $0.format == .nassau }!
        XCTAssertEqual(nassau.compact["ray"], "2&1 · AS · 5&4")
        XCTAssertEqual(nassau.compact["dave"], "L 2&1 · AS · L 5&4")
        XCTAssertEqual(r.games.first { $0.format == .skins }!.compact["ray"], "11")
        XCTAssertEqual(r.games.first { $0.format == .stableford }!.compact["tess"], "30")

        // Match play in progress: 2 up / 2 dn, then all square, then to play.
        var a: [HoleScore?] = Array(repeating: nil, count: 18); a[0] = 3; a[1] = 3
        var b: [HoleScore?] = Array(repeating: nil, count: 18); b[0] = 4; b[1] = 4
        let players = [PlayerInput(id: "a", level: 5), PlayerInput(id: "b", level: 5)]
        let live = ScoringEngine.score(RoundInput(holes: 18, par: Array(repeating: 4, count: 18), strokeIndex: [], players: players,
                                                  scores: [a, b], games: [GameInput(id: "m", format: .matchPlay, players: ["a", "b"])]))
        XCTAssertEqual(live.games[0].compact, ["a": "2 up", "b": "2 dn"])
        let square = ScoringEngine.score(RoundInput(holes: 18, par: Array(repeating: 4, count: 18), strokeIndex: [], players: players,
                                                    scores: [b, b], games: [GameInput(id: "m", format: .matchPlay, players: ["a", "b"])]))
        XCTAssertEqual(square.games[0].compact["a"], "AS")
        let unplayed = ScoringEngine.score(RoundInput(holes: 18, par: Array(repeating: 4, count: 18), strokeIndex: [], players: players,
                                                      scores: [[], []], games: [GameInput(id: "m", format: .matchPlay, players: ["a", "b"])]))
        XCTAssertEqual(unplayed.games[0].compact["a"], "—")
    }
}
