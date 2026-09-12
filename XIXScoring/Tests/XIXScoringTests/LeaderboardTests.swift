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

extension LeaderboardTests {
    /// PRD 8.11: Stableford vs Level is a passive metric. It is there on every round with par, for
    /// every player with a Level, whether or not anybody set up a Stableford game.
    func testStablefordVsLevelIsComputedWithoutAStablefordGame() {
        let input = RoundInput(
            holes: 4, par: [4, 4, 3, 5], strokeIndex: [1, 2, 3, 4],
            players: [PlayerInput(id: "a", level: 10), PlayerInput(id: "b", level: 5)],
            // a is scratch: 4, 4, 3, 5 → par every hole → 2 points each = 8.
            // b gets (10 − 5) × 2.4 = 12 strokes over four holes: three per hole.
            scores: [[.strokes(4), .strokes(4), .strokes(3), .strokes(5)],
                     [.strokes(7), .strokes(7), .strokes(6), .strokes(8)]],
            games: [], callouts: [])
        let r = ScoringEngine.score(input)
        let board = r.leaderboard[.stablefordVsLevel]
        XCTAssertNotNil(board, "no game needed")
        XCTAssertEqual(r.leaderboard[.stableford], nil, "and it is not the games' board")
        XCTAssertEqual(board?.first { $0.player == "a" }?.value, 8, "four pars off scratch")
        XCTAssertEqual(board?.first { $0.player == "b" }?.value, 8, "three strokes a hole makes his 7s net pars too")
        XCTAssertEqual(board?.map(\.rank), [1, 1], "and they are level")
    }

    func testStablefordVsLevelSkipsPlayersWithoutALevelAndRoundsWithoutPar() {
        let noLevel = RoundInput(
            holes: 2, par: [4, 4], strokeIndex: [1, 2],
            players: [PlayerInput(id: "a", level: 10), PlayerInput(id: "b")],
            scores: [[.strokes(4), .strokes(4)], [.strokes(5), .strokes(5)]],
            games: [], callouts: [])
        let board = ScoringEngine.score(noLevel).leaderboard[.stablefordVsLevel]
        XCTAssertEqual(board?.map(\.player), ["a"], "a player with no Level is left out, not guessed at")

        let noPar = RoundInput(
            holes: 2, par: [nil, nil], strokeIndex: [nil, nil],
            players: [PlayerInput(id: "a", level: 10)],
            scores: [[.strokes(4), .strokes(4)]], games: [], callouts: [])
        XCTAssertNil(ScoringEngine.score(noPar).leaderboard[.stablefordVsLevel], "no par, no points")
    }

    func testAPickedUpHoleScoresNothingInThePassiveMetric() {
        let input = RoundInput(
            holes: 2, par: [4, 4], strokeIndex: [1, 2],
            players: [PlayerInput(id: "a", level: 10)],
            scores: [[.strokes(4), .pickedUp]], games: [], callouts: [])
        XCTAssertEqual(ScoringEngine.score(input).leaderboard[.stablefordVsLevel]?.first?.value, 2,
                       "the par counts, the pick-up is zero")
    }
}
