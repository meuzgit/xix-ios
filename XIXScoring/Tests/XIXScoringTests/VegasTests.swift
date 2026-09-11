import XCTest
@testable import XIXScoring

final class VegasTests: XCTestCase {
    func testFixture() throws {
        try FixtureRunner.run("vegas_birdie_flip")
    }

    func testDigitCapAndHelpers() {
        XCTAssertEqual(VegasScorer.number(low: 4, high: 5), 45)
        XCTAssertEqual(VegasScorer.number(low: 10, high: 12), 99, "cap 9 for Vegas digits only")
        XCTAssertEqual(VegasScorer.flipped(47), 74)
    }

    func testNeedsSidesOfTwoAndTiesAreExplicit() {
        let three = RoundInput(holes: 1, par: [4], strokeIndex: [],
                               players: ["a", "b", "c"].map { PlayerInput(id: PlayerID($0)) },
                               scores: [[4], [4], [4]],
                               games: [GameInput(id: "v", format: .vegas, players: ["a", "b", "c"], sides: ["a": 0, "b": 0, "c": 1])])
        XCTAssertEqual(ScoringEngine.score(three).games[0].outcome, .unavailable(reason: "Vegas needs sides of two"))
        let tie = RoundInput(holes: 1, par: [4], strokeIndex: [],
                             players: ["a", "b", "c", "d"].map { PlayerInput(id: PlayerID($0)) },
                             scores: [[4], [5], [5], [4]],
                             games: [GameInput(id: "v", format: .vegas, players: ["a", "b", "c", "d"], sides: ["a": 0, "b": 0, "c": 1, "d": 1])])
        let r = ScoringEngine.score(tie)
        XCTAssertEqual(r.games[0].outcome, .tied(["a", "b", "c", "d"]))
        if case .vegas(let d)? = r.games.first?.detail { XCTAssertEqual(d.perHole[0].points, ["a+b": 0, "c+d": 0]) } else { XCTFail() }
    }

    func testMultiplierScalesHolePointsAndPickedUpNeverFlips() {
        let callout = CalloutInput(id: "x", hole: 1, kind: .multiplier, caller: "a", targets: ["c", "d"],
                                   params: CalloutParams(game: "v", factor: 2), responses: ["c": .signed, "d": .signed])
        // a picks up on a par 3 (6 strokes, never a birdie); c birdies → a+b flip.
        let input = RoundInput(holes: 1, par: [3], strokeIndex: [],
                               players: ["a", "b", "c", "d"].map { PlayerInput(id: PlayerID($0)) },
                               scores: [[.pickedUp], [3], [2], [4]],
                               games: [GameInput(id: "v", format: .vegas, players: ["a", "b", "c", "d"], sides: ["a": 0, "b": 0, "c": 1, "d": 1])],
                               callouts: [callout])
        let r = ScoringEngine.score(input)
        if case .vegas(let d)? = r.games.first?.detail {
            XCTAssertEqual(d.perHole[0].numbers, ["a+b": 63, "c+d": 24])
            XCTAssertEqual(d.perHole[0].points, ["a+b": 0, "c+d": 78], "(63 − 24) × 2")
        } else { XCTFail() }
    }
}
