import XCTest
@testable import XIXScoring

/// B.8 edge cases, one fixture each (B.9 names where given).
final class EdgeCaseTests: XCTestCase {
    func testB8_5_PickedUpOnParFive() throws {
        try FixtureRunner.run("pickup_par5")
    }

    func testB8_2_PlayerLeavesAfterHole6() throws {
        try FixtureRunner.run("abandon_hole6")
    }

    func testB8_2_SkinsWithOnePlayerLeftIsAbandoned() {
        var players = [PlayerInput(id: "a", level: 5), PlayerInput(id: "b", level: 5)]
        players[1].extras = PlayerExtras(leftAfterHole: 1)
        let input = RoundInput(holes: 3, par: [4, 4, 4], strokeIndex: [], players: players,
                               scores: [[3, 4, 4], [4, nil, nil]],
                               games: [GameInput(id: "s", format: .skins, players: ["a", "b"])])
        let r = ScoringEngine.score(input)
        XCTAssertEqual(r.games[0].outcome, .abandoned(by: "b"))
        if case .skins(let d)? = r.games.first?.detail { XCTAssertEqual(d.totals["a"], 1, "skins held before the departure stay") } else { XCTFail() }
        XCTAssertTrue(r.medals.isEmpty)
        XCTAssertEqual(r.rivalPoints, ["a": 0, "b": 0])
    }

    func testB8_3_AllTiedSkinsCarryIsVoid() throws {
        try FixtureRunner.run("skins_all_tied")
    }

    func testB8_1_NineHolesWithoutPar() throws {
        try FixtureRunner.run("nine_hole_no_par")
    }

    func testB8_4_SkinsValidation() throws {
        try FixtureRunner.run("skins_validation")
    }

    func testB8_6_MatchPlayDecidedEarly() throws {
        try FixtureRunner.run("two_player_matchplay")
    }
}
