import XCTest
@testable import XIXScoring

final class StablefordTests: XCTestCase {
    private func input(holes: Int = 4, par: [Int?] = [4, 5, 3, 4], players: [String] = ["a", "b"],
                       scores: [[HoleScore?]], options: Options = Options(), levels: [Double?]? = nil,
                       callouts: [CalloutInput] = []) -> RoundInput {
        RoundInput(holes: holes, par: par, strokeIndex: [],
                   players: players.enumerated().map { i, id in
                       let level: Double? = levels == nil ? 5 : levels![i]
                       return PlayerInput(id: PlayerID(id), level: level)
                   },
                   scores: scores,
                   games: [GameInput(id: "st", format: .stableford, options: options, players: players.map { PlayerID($0) })],
                   callouts: callouts)
    }

    private func detail(_ r: RoundResult) -> StablefordDetail? {
        if case .stableford(let d)? = r.games.first?.detail { return d }
        return nil
    }

    func testStandardTable() {
        let t = StablefordTable.standard
        XCTAssertEqual([-3, -2, -1, 0, 1, 2, 5].map(t.points), [4, 4, 3, 2, 1, 0, 0])
        let m = StablefordTable.modified
        XCTAssertEqual([-4, -3, -2, -1, 0, 1, 2, 5].map(m.points), [8, 8, 5, 2, 0, -1, -3, -3])
    }

    func testPointsTotalsAndOutcome() {
        // a: eagle, par, bogey, double → 4+2+1+0 = 7. b: par ×4 → 8.
        let r = ScoringEngine.score(input(scores: [[2, 5, 4, 6], [4, 5, 3, 4]]))
        let d = detail(r)!
        XCTAssertEqual(d.points["a"], [4, 2, 1, 0])
        XCTAssertEqual(d.points["b"], [2, 2, 2, 2])
        XCTAssertEqual(d.totals, ["a": 7, "b": 8])
        XCTAssertEqual(d.table, "standard")
        XCTAssertEqual(r.games[0].outcome, .winner("b"))
        XCTAssertEqual(r.games[0].display["b"], "Stableford 8")
        XCTAssertEqual(r.games[0].standings.map(\.player), ["b", "a"])
    }

    func testPickedUpScoresZeroEvenOnModifiedTable() {
        // B.4.1, B.8.5: a pick-up is 0 points, not the table's worst value.
        let r = ScoringEngine.score(input(scores: [[.pickedUp, 5, 3, 4], [4, 5, 3, 4]], options: Options(table: .modified)))
        let d = detail(r)!
        XCTAssertEqual(d.points["a"], [0, 0, 0, 0])
        XCTAssertEqual(d.table, "modified")
        let standard = detail(ScoringEngine.score(input(scores: [[.pickedUp, 5, 3, 4], [4, 5, 3, 4]])))!
        XCTAssertEqual(standard.points["a"]?[0], 0)
    }

    func testUnavailableWhenAPlayedHoleHasNoPar() {
        // B.8.1
        let r = ScoringEngine.score(input(par: [4, nil, 3, 4], scores: [[4, 5, 3, 4], [4, 5, 3, 4]]))
        XCTAssertEqual(r.games[0].outcome, .unavailable(reason: "Stableford needs par on every played hole; missing on 2"))
        // Not yet played: still available through hole 1.
        let early = ScoringEngine.score(input(par: [4, nil, 3, 4], scores: [[4, nil, nil, nil], [4, nil, nil, nil]]))
        XCTAssertEqual(detail(early)?.points["a"], [2])
        XCTAssertNil(early.games[0].outcome)
    }

    func testNetStablefordAndMissingLevel() {
        // B.8.14. a: Level 9.5 → 1 stroke, evenly → hole 1. Net 4 on par 4 = 2 pts; b gross 5 = 1 pt.
        let r = ScoringEngine.score(input(scores: [[5, 5, 3, 4], [5, 5, 3, 4]], options: Options(net: true), levels: [9.5, 10]))
        XCTAssertEqual(detail(r)?.points["a"]?[0], 2)
        XCTAssertEqual(detail(r)?.points["b"]?[0], 1)
        let missing = ScoringEngine.score(input(scores: [[5, 5, 3, 4], [5, 5, 3, 4]], options: Options(net: true), levels: [9.5, nil]))
        guard case .unavailable(let reason)? = missing.games[0].outcome else { return XCTFail("expected unavailable") }
        XCTAssertTrue(reason.contains("Level"), reason)
    }

    func testMultiplierScalesThatHolesPoints() {
        let callout = CalloutInput(id: "x", hole: 2, kind: .multiplier, caller: "a", targets: ["b"],
                                   params: CalloutParams(game: "st", factor: 2), status: .signed, responder: "b")
        let r = ScoringEngine.score(input(scores: [[4, 4, 3, 4], [4, 5, 3, 4]], callouts: [callout]))
        XCTAssertEqual(detail(r)?.points["a"], [2, 6, 2, 2])
        XCTAssertEqual(detail(r)?.points["b"], [2, 4, 2, 2])
    }

    func testTiedOutcomeAndInProgressStandings() {
        let tied = ScoringEngine.score(input(scores: [[4, 5, 3, 4], [4, 5, 3, 4]]))
        XCTAssertEqual(tied.games[0].outcome, .tied(["a", "b"]))
        XCTAssertEqual(tied.games[0].standings.map(\.rank), [1, 1])
        let partial = ScoringEngine.score(input(scores: [[4, 5, nil, 4], [4, 5, 3, 4]]))
        XCTAssertEqual(partial.games[0].throughHole, 2)
        XCTAssertEqual(detail(partial)?.totals, ["a": 4, "b": 4])
        XCTAssertNil(partial.games[0].outcome)
    }
}
