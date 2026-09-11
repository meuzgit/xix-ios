import XCTest
@testable import XIXScoring

final class StrokePlayTests: XCTestCase {
    func testFixture() throws {
        try FixtureRunner.run("stroke_play")
    }

    func testTiedLowGrossSharesTheMedalAndInProgressHasNoOutcome() {
        var input = RoundInput(holes: 3, par: [4, 4, 4], strokeIndex: [],
                               players: [PlayerInput(id: "a", level: 5), PlayerInput(id: "b", level: 5)],
                               scores: [[4, 5, 4], [5, 4, 4]],
                               games: [GameInput(id: "g", format: .strokePlay, players: ["a", "b"])])
        let tied = ScoringEngine.score(input)
        XCTAssertEqual(tied.games[0].outcome, .tied(["a", "b"]))
        XCTAssertEqual(tied.medals.map(\.key), [.strokeLowGross, .strokeLowGross])
        XCTAssertEqual(tied.rivalPoints, ["a": 5, "b": 5])
        input.scores[1][2] = nil
        let partial = ScoringEngine.score(input)
        XCTAssertEqual(partial.games[0].throughHole, 2)
        XCTAssertNil(partial.games[0].outcome)
        if case .strokePlay(let d)? = partial.games.first?.detail {
            XCTAssertEqual(d.strokes["a"], [4, 5])
            XCTAssertEqual(d.totals["a"], 9)
        } else { XCTFail() }
    }

    func testPickedUpCountsDoubleParAndNetNeedsLevels() {
        let input = RoundInput(holes: 2, par: [5, nil], strokeIndex: [],
                               players: [PlayerInput(id: "a", level: 5), PlayerInput(id: "b")],
                               scores: [[.pickedUp, .pickedUp], [4, 4]],
                               games: [GameInput(id: "g", format: .strokePlay, players: ["a", "b"]),
                                       GameInput(id: "n", format: .strokePlay, options: Options(net: true), players: ["a", "b"])])
        let r = ScoringEngine.score(input)
        if case .strokePlay(let d)? = r.games.first?.detail { XCTAssertEqual(d.strokes["a"], [10, 10]) } else { XCTFail() }
        XCTAssertEqual(r.games[0].outcome, .winner("b"))
        XCTAssertTrue(r.games[1].outcome?.isUnavailable ?? false)
    }
}
