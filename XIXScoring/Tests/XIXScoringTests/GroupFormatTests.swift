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
