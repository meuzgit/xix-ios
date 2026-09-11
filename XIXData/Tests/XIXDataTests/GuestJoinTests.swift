import Supabase
import XCTest
@testable import XIXData
@testable import XIXModels

/// D.5: guest join via link → claim row → score own row; the owner can still edit it.
final class GuestJoinTests: XCTestCase {
    func testGuestJoinsClaimsScoresAndOwnerCanEdit() async throws {
        let ray = try await LocalSupabase.client(as: LocalSupabase.ray, email: "ray@privaterelay.appleid.com", label: "ray-guest")
        let bundle = try await LocalSupabase.freshRound(owner: ray, guestNames: ["Guest"])

        // A brand-new person taps the link: sign in with Apple happens at claim time; here we mint their session.
        let admin = LocalSupabase.service
        let email = "guest-\(UUID().uuidString.prefix(8))@privaterelay.appleid.com"
        let user = try await admin.auth.admin.createUser(attributes: AdminUserAttributes(email: email, emailConfirm: true, userMetadata: ["display_name": .string("Guest")]))
        let guest = try await LocalSupabase.client(as: user.id, email: email, label: "guest")

        let repo = RoundRepository(client: guest)
        let round = try await repo.joinRound(code: bundle.round.joinCode)
        XCTAssertEqual(round.id, bundle.round.id)
        let rows = try await repo.joinableRows(code: bundle.round.joinCode)
        XCTAssertEqual(rows.map(\.displayName), ["Guest"])
        let claimed = try await repo.claimRow(roundID: round.id, playerID: rows[0].id)
        XCTAssertEqual(claimed.profileId, user.id)

        let session = RoundSession(client: guest, roundID: round.id, connectivity: Connectivity(startMonitoring: false))
        try await session.start()
        let ownerSession = RoundSession(client: ray, roundID: round.id, connectivity: Connectivity(startMonitoring: false))
        try await ownerSession.start()
        try await Task.sleep(for: .milliseconds(500))

        await session.enterScore(playerID: claimed.id, hole: 1, strokes: 5, pickedUp: false)
        await LocalSupabase.waitUntil(5, "owner sees the guest's score") {
            await ownerSession.currentState().score(player: claimed.id, hole: 1)?.strokes == 5
        }
        await ownerSession.enterScore(playerID: claimed.id, hole: 1, strokes: 6, pickedUp: false)
        await LocalSupabase.waitUntil(5, "guest sees the owner's edit") {
            await session.currentState().score(player: claimed.id, hole: 1)?.strokes == 6
        }
        // A guest cannot write another row: the server refuses, the local cell is reverted, one rejection reported.
        var rejected = 0
        let events = await session.events()
        let watcher = Task { for await e in events { if case .rejected = e { rejected += 1; break } } }
        let rayRow = bundle.players.first { $0.displayName == "Ray" }!.id
        await session.enterScore(playerID: rayRow, hole: 1, strokes: 3, pickedUp: false)
        await LocalSupabase.waitUntil(5, "rejection") { rejected == 1 }
        watcher.cancel()
        let reverted = await session.currentState().score(player: rayRow, hole: 1)
        XCTAssertNil(reverted, "reverted: Ray has no hole 1 on the server")
        await session.stop()
        await ownerSession.stop()
    }
}
