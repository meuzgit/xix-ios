import XCTest
@testable import XIXScoring

final class SkinsTests: XCTestCase {
    private func input(holes: Int = 3, par: [Int?] = [4, 4, 4], players: [String] = ["a", "b", "c"],
                       scores: [[HoleScore?]], options: Options = Options(), callouts: [CalloutInput] = []) -> RoundInput {
        RoundInput(holes: holes, par: par, strokeIndex: [],
                   players: players.map { PlayerInput(id: PlayerID($0), level: 5) },
                   scores: scores,
                   games: [GameInput(id: "s", format: .skins, options: options, players: players.map { PlayerID($0) })],
                   callouts: callouts)
    }

    private func skins(_ result: RoundResult) -> SkinsDetail? {
        if case .skins(let d)? = result.games.first?.detail { return d }
        return nil
    }

    func testCarryoverAndCarryCleared() {
        let r = ScoringEngine.score(input(scores: [[4, 4, 3], [4, 5, 4], [5, 4, 4]]))
        let d = skins(r)!
        XCTAssertEqual(d.perHole.map(\.carryAfter), [1, 2, 0])
        XCTAssertEqual(d.perHole.map(\.skins), [0, 0, 3])
        XCTAssertEqual(d.totals, ["a": 3, "b": 0, "c": 0])
        XCTAssertEqual(r.holeEvents.map(\.text), ["Halved. 1 carrying to 2.", "Halved. 2 carrying to 3.", "Skin to A. Carry cleared."])
        XCTAssertEqual(r.games[0].outcome, .winner("a"))
        XCTAssertEqual(r.leaderboard[.skins]?.map(\.player), ["a", "b", "c"])
        XCTAssertEqual(r.leaderboard[.skins]?.map(\.rank), [1, 2, 2])
    }

    func testAllHolesTiedCarryIsVoidAtTheEnd() {
        // B.8.3
        let r = ScoringEngine.score(input(scores: [[4, 4, 4], [4, 4, 4], [4, 4, 4]]))
        let d = skins(r)!
        XCTAssertEqual(d.perHole.map(\.carryAfter), [1, 2, 3])
        XCTAssertEqual(d.voidCarry, 3)
        XCTAssertEqual(d.carry, 0)
        XCTAssertEqual(d.totals, ["a": 0, "b": 0, "c": 0])
        // Approved ink wording for a void carry on the last hole; keep exact.
        XCTAssertEqual(r.holeEvents.last?.text, "Halved. 3 void.")
        XCTAssertEqual(r.games[0].outcome, .void, "nobody won a skin: no winner, not an all-way tie")
    }

    func testValidationBogeyDoesNotTakeTheCarry() {
        // B.8.4: carry of 3 won by a bogey → not awarded, carry continues.
        let r = ScoringEngine.score(input(holes: 5, par: [4, 4, 4, 4, 4],
                                          scores: [[4, 4, 4, 5, 4], [4, 4, 4, 6, 5], [4, 4, 4, 6, 5]],
                                          options: Options(validation: true)))
        let d = skins(r)!
        XCTAssertEqual(d.perHole[3].winner, nil)
        XCTAssertEqual(d.perHole[3].unvalidated, "a")
        XCTAssertEqual(d.perHole[3].carryAfter, 4)
        // Approved ink wording for a failed validation; keep exact.
        XCTAssertEqual(r.holeEvents[3].text, "A takes the hole but not the carry. 4 carrying to 5.")
        XCTAssertEqual(d.perHole[4].winner, "a")
        XCTAssertEqual(d.perHole[4].skins, 5, "par on the next hole takes the whole carry")
        XCTAssertEqual(d.totals["a"], 5)
    }

    func testNoCarryoverHalvedHolesAreSimplyVoid() {
        let r = ScoringEngine.score(input(scores: [[4, 4, 3], [4, 5, 4], [5, 4, 4]], options: Options(carryover: false)))
        let d = skins(r)!
        XCTAssertEqual(d.perHole.map(\.carryAfter), [0, 0, 0])
        XCTAssertEqual(d.totals["a"], 1)
        XCTAssertEqual(r.holeEvents.map(\.text), ["Halved.", "Halved.", "Skin to A."])
    }

    func testMultiplierCalloutOnHalvedHoleRaisesCarryByFactor() {
        // B.8.9
        let callout = CalloutInput(id: "m", hole: 2, kind: .multiplier, caller: "a", targets: ["b", "c"],
                                   params: CalloutParams(game: "s", factor: 3), status: .signed, responder: "b")
        let r = ScoringEngine.score(input(scores: [[4, 4, 3], [4, 4, 4], [5, 4, 4]], callouts: [callout]))
        let d = skins(r)!
        XCTAssertEqual(d.perHole.map(\.carryAfter), [1, 4, 0])
        XCTAssertEqual(d.perHole[2].skins, 5)
        XCTAssertEqual(r.holeEvents[1].text, "Halved. 4 carrying to 3.")
    }

    func testMultiplierCalloutOnWonHoleIsWorthFactorSkins() {
        let callout = CalloutInput(id: "m", hole: 1, kind: .multiplier, caller: "a", targets: ["b", "c"],
                                   params: CalloutParams(game: "s", factor: 2), status: .signed, responder: "b")
        let r = ScoringEngine.score(input(scores: [[3, 4, 4], [4, 4, 4], [5, 4, 4]], callouts: [callout]))
        XCTAssertEqual(skins(r)!.perHole[0].skins, 2)
        let unsigned = CalloutInput(id: "m", hole: 1, kind: .multiplier, caller: "a", targets: ["b", "c"],
                                    params: CalloutParams(game: "s", factor: 2), status: .ducked, responder: "b")
        XCTAssertEqual(skins(ScoringEngine.score(input(scores: [[3, 4, 4], [4, 4, 4], [5, 4, 4]], callouts: [unsigned])))!.perHole[0].skins, 1)
    }

    func testUnresolvedHoleStopsTheCarry() {
        // B.4.2: hole 2 missing for c → through 1; carry waits.
        let r = ScoringEngine.score(input(scores: [[4, 3, 3], [4, 4, 4], [4, nil, 4]]))
        let d = skins(r)!
        XCTAssertEqual(r.games[0].throughHole, 1)
        XCTAssertEqual(d.perHole.count, 1)
        XCTAssertEqual(d.carry, 1)
        XCTAssertEqual(d.voidCarry, 0)
        XCTAssertNil(r.games[0].outcome)
        XCTAssertEqual(r.status, .inProgress(throughHole: 1))
    }

    func testTwoPlayersAllowedAndOnePlayerUnavailable() {
        // B.8.13
        let two = ScoringEngine.score(input(players: ["a", "b"], scores: [[3, 4, 4], [4, 4, 4]]))
        XCTAssertEqual(skins(two)?.totals["a"], 1)
        let one = ScoringEngine.score(input(players: ["a"], scores: [[3, 4, 4]]))
        XCTAssertEqual(one.games[0].outcome, .unavailable(reason: "Skins needs at least two players"))
    }

    func testNetSkinsNeedsALevelForEveryPlayer() {
        // B.8.14
        var i = input(scores: [[4, 4, 3], [4, 5, 4], [5, 4, 4]], options: Options(net: true))
        i.players[1].level = nil
        let r = ScoringEngine.score(i)
        guard case .unavailable(let reason)? = r.games[0].outcome else { return XCTFail("expected unavailable") }
        XCTAssertTrue(reason.contains("b"), reason)
        XCTAssertNil(r.leaderboard[.skins])
    }

    func testNetSkinsUsesNetStrokes() {
        // a: Level 5 → 12 strokes, evenly over 3 holes → 4 per hole. b, c: Level 10 → 0.
        var i = input(scores: [[8, 8, 8], [5, 5, 5], [5, 5, 5]], options: Options(net: true))
        i.players[1].level = 10
        i.players[2].level = 10
        let r = ScoringEngine.score(i)
        XCTAssertEqual(skins(r)?.totals, ["a": 3, "b": 0, "c": 0])
    }

    func testTiedOutcomeIsExplicit() {
        let r = ScoringEngine.score(input(scores: [[3, 4, 4], [4, 3, 4], [4, 4, 4]]))
        XCTAssertEqual(r.games[0].outcome, .tied(["a", "b"]))
        XCTAssertEqual(r.games[0].standings.map(\.rank), [1, 1, 3])
        XCTAssertEqual(r.games[0].display["a"], "Skins 1")
    }
}
