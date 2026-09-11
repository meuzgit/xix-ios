import XCTest
@testable import XIXScoring

final class LeaderboardTests: XCTestCase {
    func testGrossAscendingTiesShareRankInSeatOrder() {
        let input = RoundInput(holes: 2, par: [4, 4], strokeIndex: [],
                               players: ["a", "b", "c", "d"].map { PlayerInput(id: PlayerID($0), level: 5) },
                               scores: [[5, 5], [4, 4], [4, 4], [3, 6]])
        let r = ScoringEngine.score(input)
        XCTAssertEqual(r.leaderboard[.gross]?.map(\.player), ["b", "c", "d", "a"])
        XCTAssertEqual(r.leaderboard[.gross]?.map(\.value), [8, 8, 9, 10])
        XCTAssertEqual(r.leaderboard[.gross]?.map(\.rank), [1, 1, 3, 4])
        XCTAssertEqual(r.leaderboard[.toPar]?.map(\.value), [0, 0, 1, 2])
        XCTAssertEqual(r.leaderboard[.net]?.map(\.rank), [1, 1, 3, 4])
    }

    func testPlayersWithNoHolesAreLeftOffScoreBoards() {
        let input = RoundInput(holes: 2, par: [4, nil], strokeIndex: [],
                               players: [PlayerInput(id: "a"), PlayerInput(id: "b")],
                               scores: [[5, 5], [nil, nil]])
        let r = ScoringEngine.score(input)
        XCTAssertEqual(r.leaderboard[.gross]?.map(\.player), ["a"])
        XCTAssertNil(r.leaderboard[.toPar], "par unknown on a played hole")
        XCTAssertNil(r.leaderboard[.net], "no Level")
    }
}
