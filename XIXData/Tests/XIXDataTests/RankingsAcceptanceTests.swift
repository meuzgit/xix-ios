// Build Doc 3 step 5's acceptance, without a screen: three rounds across two accounts, then the
// rivalry and both boards checked against a tally worked out by hand below.
//
// Needs `supabase functions serve --no-verify-jwt` so the engine webhook can answer; set
// XIX_ACCEPTANCE=1 (make rankings-acceptance).
import Foundation
import Supabase
import XCTest
@testable import XIXData
@testable import XIXModels
import XIXScoring

final class RankingsAcceptanceTests: XCTestCase {
    // Three rounds, nine holes, par 4 throughout. Ray and Dave both play every one; the scores are
    // chosen so every number below can be worked out on paper.
    //
    //          hole   1  2  3  4  5  6  7  8  9    gross   to par   birdies
    //  round 1  Ray    3  4  4  4  4  4  4  4  4      35      -1        1
    //           Dave   4  4  4  4  4  4  4  4  5      37      +1        0
    //  round 2  Ray    4  4  4  4  4  4  4  4  4      36       0        0
    //           Dave   3  3  4  4  4  4  4  4  4      34      -2        2
    //  round 3  Ray    3  3  3  4  4  4  4  4  4      33      -3        3
    //           Dave   4  4  4  4  4  4  4  4  4      36       0        0
    //
    //  Head to head: Ray wins round 1 (35 v 37) and round 3 (33 v 36); Dave wins round 2 (34 v 36).
    //  Birdies: Ray 1 + 0 + 3 = 4. Dave 0 + 2 + 0 = 2.
    //  Rounds played: 3 each.
    //  Stableford vs Level: both enter an index before they play, the way Settings lets them. Ray's 5
    //  gives him a stroke on holes 1–5; Dave's 8 gives him one on holes 1–8 (no stroke index on this
    //  course, so the strokes fall in hole order). Standard table, net against par 4:
    //
    //    Ray    r1  net 2,3,3,3,3,4,4,4,4  →  4+3+3+3+3+2+2+2+2 = 24
    //           r2  net 3,3,3,3,3,4,4,4,4  →  3×5 + 2×4         = 23
    //           r3  net 2,2,2,3,3,4,4,4,4  →  4+4+4+3+3+2+2+2+2 = 26     total 73
    //    Dave   r1  net 3,3,3,3,3,3,3,3,5  →  3×8 + 1           = 25
    //           r2  net 2,2,3,3,3,3,3,3,4  →  4+4+3×6+2         = 28
    //           r3  net 3,3,3,3,3,3,3,3,4  →  3×8 + 2           = 26     total 79
    static let rayScores = [[3, 4, 4, 4, 4, 4, 4, 4, 4], [4, 4, 4, 4, 4, 4, 4, 4, 4], [3, 3, 3, 4, 4, 4, 4, 4, 4]]
    static let daveScores = [[4, 4, 4, 4, 4, 4, 4, 4, 5], [3, 3, 4, 4, 4, 4, 4, 4, 4], [4, 4, 4, 4, 4, 4, 4, 4, 4]]

    var ray: XIXClient!
    var dave: XIXClient!
    var roundIDs: [UUID] = []

    override func setUp() async throws {
        guard ProcessInfo.processInfo.environment["XIX_ACCEPTANCE"] != nil else {
            throw XCTSkip("set XIX_ACCEPTANCE=1 with `supabase functions serve` running (make rankings-acceptance)")
        }
        try XCTSkipIf(LocalSupabase.isRemote, "runs against the local stack")
        ray = try await LocalSupabase.client(as: LocalSupabase.ray, email: "ray@privaterelay.appleid.com", label: "ray-\(name)")
        dave = try await LocalSupabase.client(as: LocalSupabase.dave, email: "dave@privaterelay.appleid.com", label: "dave-\(name)")
        // Each enters their own index, as Settings lets them (PRD 8.21). Without a Level there is no
        // Stableford vs Level to rank — which is correct, and is why this is the first thing they do.
        try await AuthService(client: ray).updateLevelIndex(5)
        try await AuthService(client: dave).updateLevelIndex(8)
    }

    func testThreeRoundsAddUpOnTheBoardsAndInTheRivalry() async throws {
        var perRoundStableford: [String: [Int]] = ["Ray": [], "Dave": []]

        for round in 0..<3 {
            let bundle = try await RoundRepository(client: ray).createRound(
                course: CourseDraft(name: "Tally Links", region: "Local", par: Array(repeating: 4, count: 9)),
                holes: 9, ownerName: "Ray", guestNames: ["Dave"])
            roundIDs.append(bundle.round.id)
            let rayRow = bundle.players.first { $0.displayName == "Ray" }!.id
            let daveRow = bundle.players.first { $0.displayName == "Dave" }!.id
            try await RoundRepository(client: dave).claimRow(roundID: bundle.round.id, playerID: daveRow)

            let session = RoundSession(client: ray, roundID: bundle.round.id, connectivity: Connectivity(startMonitoring: false))
            try await session.start()
            for hole in 1...9 {
                await session.enterScore(playerID: rayRow, hole: hole, strokes: Self.rayScores[round][hole - 1], pickedUp: false)
                await session.enterScore(playerID: daveRow, hole: hole, strokes: Self.daveScores[round][hole - 1], pickedUp: false)
            }
            await LocalSupabase.waitUntil(30, "round \(round + 1) acknowledged") { await session.pendingWrites() == 0 }
            try await RoundRepository(client: ray).endRound(roundID: bundle.round.id)

            // The engine runs on the server, through the webhook, exactly as it does in the app.
            await LocalSupabase.waitUntil(60, "the engine's result for round \(round + 1)") {
                let rows = try? await LocalSupabase.service.schema("xix").from("results").select("round_id")
                    .eq("round_id", value: bundle.round.id).execute()
                return (rows?.data.count ?? 0) > 4
            }
            // Dave confirms, so it counts now rather than in 48 hours.
            _ = try await RoundRepository(client: dave).confirmRound(roundID: bundle.round.id, action: .confirm)

            // Keep each round's own Stableford-vs-Level number, to add up at the end.
            await session.resync()
            let state = await session.currentState()
            let result = try XCTUnwrap(state.serverResult, "the server's result reached the session")
            for (name, row) in [("Ray", rayRow), ("Dave", daveRow)] {
                let id = PlayerID(row.uuidString.lowercased())
                let points = result.leaderboard[.stablefordVsLevel]?.first { $0.player == id }?.value
                perRoundStableford[name]?.append(try XCTUnwrap(points, "\(name) has a Stableford vs Level score"))
            }
            await session.stop()
        }

        // The nightly job, run now.
        _ = try await LocalSupabase.service.schema("xix").rpc("refresh_rankings").execute()

        let repo = CabinetRepository(client: ray)

        // Rounds played: three each, and nobody else is on the board.
        let rounds = try await repo.rankings(.rounds)
        XCTAssertEqual(rounds.first { $0.displayName == "Ray" }?.value, 3)
        XCTAssertEqual(rounds.first { $0.displayName == "Dave" }?.value, 3)

        // Birdies, all time: Ray 4, Dave 2 — counted off the card above.
        let birdies = try await repo.rankings(.birdies)
        XCTAssertEqual(birdies.first { $0.displayName == "Ray" }?.value, 4, "1 + 0 + 3")
        XCTAssertEqual(birdies.first { $0.displayName == "Dave" }?.value, 2, "0 + 2 + 0")
        XCTAssertEqual(birdies.first { $0.displayName == "Ray" }?.rank, 1, "and Ray is top of that board")
        XCTAssertEqual(birdies.first { $0.isMe }?.displayName, "Ray", "the board knows which row is the reader's")

        // Stableford vs Level: each round's points, and the board as their sum. The numbers are the
        // ones worked out by hand at the top of this file.
        XCTAssertEqual(perRoundStableford["Ray"], [24, 23, 26], "Ray's three rounds, off a 5 index")
        XCTAssertEqual(perRoundStableford["Dave"], [25, 28, 26], "Dave's three, off an 8")
        let stableford = try await repo.rankings(.stablefordVsLevel)
        XCTAssertEqual(stableford.first { $0.displayName == "Ray" }?.value, 73, "24 + 23 + 26")
        XCTAssertEqual(stableford.first { $0.displayName == "Dave" }?.value, 79, "25 + 28 + 26")
        XCTAssertEqual(stableford.first { $0.rank == 1 }?.displayName, "Dave", "and the strokes put Dave top of that board")

        // Rival Points: the same sum, from the engine's own per-round totals.
        var rivalPoints: [String: Double] = ["Ray": 0, "Dave": 0]
        for id in roundIDs {
            struct PayloadOnly: Decodable { let payload: JSONValueLite }
            let raw = try await LocalSupabase.service.schema("xix").from("results").select("payload")
                .eq("round_id", value: id).execute().data
            let payload = try JSONSerialization.jsonObject(with: raw) as? [[String: Any]]
            let points = (payload?.first?["payload"] as? [String: Any])?["rivalPoints"] as? [String: Any] ?? [:]
            let players: [PlayerRow] = try await LocalSupabase.service.schema("xix").from("players").select()
                .eq("round_id", value: id).execute().value
            for player in players {
                guard let name = ["Ray", "Dave"].first(where: { $0 == player.displayName }) else { continue }
                let value = points[player.id.uuidString.lowercased()] as? Double
                    ?? Double(points[player.id.uuidString.lowercased()] as? Int ?? 0)
                rivalPoints[name]? += value
            }
        }
        let board = try await repo.rankings(.rivalPoints)
        for name in ["Ray", "Dave"] {
            XCTAssertEqual(board.first { $0.displayName == name }?.value, rivalPoints[name],
                           "\(name)'s Rival Points are the three rounds added up")
        }

        // The rivalry: two wins to Ray, one to Dave, over three rounds.
        let rivalry = try await repo.rivalry(with: LocalSupabase.dave)
        XCTAssertEqual(rivalry.rounds, 3)
        XCTAssertEqual(rivalry.myWins, 2, "35 v 37 and 33 v 36")
        XCTAssertEqual(rivalry.theirWins, 1, "34 v 36")
        XCTAssertEqual(rivalry.halved, 0)
        XCTAssertEqual(rivalry.them, "Dave")
        XCTAssertEqual(rivalry.lastFive.count, 3, "only three have been played")
        XCTAssertEqual(rivalry.lastFive.first?.outcome, "W", "the most recent is Ray's")

        // And from Dave's side it is the same rivalry, the other way round.
        let theirs = try await CabinetRepository(client: dave).rivalry(with: LocalSupabase.ray)
        XCTAssertEqual(theirs.myWins, 1)
        XCTAssertEqual(theirs.theirWins, 2)

        // A crew board of the two of them ranks the same numbers among themselves.
        let crew = try await repo.createCrew(name: "Tally Crew")
        try await repo.addToCrew(crewID: crew.id, profileID: LocalSupabase.dave)
        let crewBirdies = try await repo.rankings(.birdies, crewID: crew.id)
        XCTAssertEqual(crewBirdies.map(\.displayName), ["Ray", "Dave"], "top first, and only the crew")
        XCTAssertEqual(crewBirdies.map(\.rank), [1, 2])
    }

    override func tearDown() async throws {
        let db = LocalSupabase.service.schema("xix")
        for id in roundIDs { try? await db.from("rounds").delete().eq("id", value: id).execute() }
        try? await db.from("crews").delete().eq("name", value: "Tally Crew").execute()
    }
}

/// Just enough to decode a payload column without the row decoder's conventions.
struct JSONValueLite: Decodable {}
