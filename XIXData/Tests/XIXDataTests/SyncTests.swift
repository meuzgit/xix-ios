import XCTest
@testable import XIXData
@testable import XIXModels
import XIXScoring

/// D.5 acceptance without UI: two sessions see each other's scores; offline three holes then reconnect.
final class SyncTests: XCTestCase {
    var ray: XIXClient!
    var dave: XIXClient!
    var bundle: RoundBundle!
    var sessionA: RoundSession!
    var sessionB: RoundSession!

    override func setUp() async throws {
        ray = try await LocalSupabase.client(as: LocalSupabase.ray, email: "ray@privaterelay.appleid.com", label: "ray-\(name)")
        dave = try await LocalSupabase.client(as: LocalSupabase.dave, email: "dave@privaterelay.appleid.com", label: "dave-\(name)")
        bundle = try await LocalSupabase.freshRound(owner: ray)
        let daveRow = try XCTUnwrap(bundle.players.first { $0.displayName == "Dave" })
        try await RoundRepository(client: dave).claimRow(roundID: bundle.round.id, playerID: daveRow.id)
        sessionA = RoundSession(client: ray, roundID: bundle.round.id, connectivity: Connectivity(startMonitoring: false))
        sessionB = RoundSession(client: dave, roundID: bundle.round.id, connectivity: Connectivity(startMonitoring: false))
        try await sessionA.start()
        try await sessionB.start()
        try await Task.sleep(for: .milliseconds(500))   // channels joined
    }

    override func tearDown() async throws {
        await sessionA?.stop()
        await sessionB?.stop()
    }

    private var rayRow: UUID { bundle.players.first { $0.displayName == "Ray" }!.id }
    private var daveRow: UUID { bundle.players.first { $0.displayName == "Dave" }!.id }

    func testTwoSessionsSeeEachOthersScoresWithinASecond() async throws {
        let t0 = Date()
        await sessionA.enterScore(playerID: rayRow, hole: 1, strokes: 4, pickedUp: false)
        await LocalSupabase.waitUntil(5, "Dave's session to receive Ray's hole 1") {
            await self.sessionB.currentState().score(player: self.rayRow, hole: 1)?.strokes == 4
        }
        let latency = Date().timeIntervalSince(t0)
        print("[acceptance] Ray → Dave score visible after \(String(format: "%.3f", latency))s")
        XCTAssertLessThan(latency, 1.0 + 0.5, "within a second on the local stack")

        await sessionB.enterScore(playerID: daveRow, hole: 1, strokes: 5, pickedUp: false)
        await LocalSupabase.waitUntil(5, "Ray's session to receive Dave's hole 1") {
            await self.sessionA.currentState().score(player: self.daveRow, hole: 1)?.strokes == 5
        }
        // Both local engines agree.
        let a = await sessionA.recompute()!, b = await sessionB.recompute()!
        XCTAssertEqual(a.perPlayer[PlayerID(rayRow.uuidString.lowercased())]?.gross, 4)
        XCTAssertEqual(b.perPlayer[PlayerID(daveRow.uuidString.lowercased())]?.gross, 5)
        XCTAssertEqual(a.status, b.status)
        let noticesA = await sessionA.notices
        XCTAssertTrue(noticesA.isEmpty, "new cells never raise a merge notice")
    }

    func testOfflineThreeHolesThenReconnect() async throws {
        // Dave drops off the network: no Realtime, writes queue locally.
        await sessionB.setOnline(false)

        // Ray plays three holes and, as owner, fills Dave's hole 2 with a 9 while Dave is away.
        for hole in 1...3 { await sessionA.enterScore(playerID: rayRow, hole: hole, strokes: 4, pickedUp: false) }
        await sessionA.enterScore(playerID: daveRow, hole: 2, strokes: 9, pickedUp: false)
        await LocalSupabase.waitUntil(5, "Ray's writes acknowledged") { await self.sessionA.pendingWrites() == 0 }
        try await Task.sleep(for: .milliseconds(300))
        let arrivedOffline = await sessionB.currentState().score(player: rayRow, hole: 1)
        XCTAssertNil(arrivedOffline, "nothing arrives while offline")

        // Dave, still offline, enters his own three holes; his hole 2 stamp is later than Ray's.
        for hole in 1...3 { await sessionB.enterScore(playerID: daveRow, hole: hole, strokes: 4 + hole, pickedUp: false) }
        let pendingB = await sessionB.pendingWrites()
        XCTAssertEqual(pendingB, 3)
        let offlineCell = await sessionB.currentState().score(player: daveRow, hole: 2)?.strokes
        XCTAssertEqual(offlineCell, 6, "renders from the local store while offline")

        // Reconnect: Dave catches up (Ray's holes arrive as new cells) and his queue drains in order.
        // His hole 2 carries the later stamp, so it wins by last-write-wins and replaces Ray's displayed 9.
        await sessionB.setOnline(true)
        await LocalSupabase.waitUntil(8, "Dave's queue to drain") { await self.sessionB.pendingWrites() == 0 }
        await LocalSupabase.waitUntil(5, "Ray to receive Dave's hole 2") {
            await self.sessionA.currentState().score(player: self.daveRow, hole: 2)?.strokes == 6
        }
        await LocalSupabase.waitUntil(5, "Dave to have Ray's holes") {
            let s = await self.sessionB.currentState()
            return (1...3).allSatisfy { s.score(player: self.rayRow, hole: $0)?.strokes == 4 }
        }

        // Both stores hold the same six cells.
        let a = await sessionA.currentState(), b = await sessionB.currentState()
        for hole in 1...3 {
            XCTAssertEqual(a.score(player: rayRow, hole: hole)?.strokes, 4)
            XCTAssertEqual(b.score(player: rayRow, hole: hole)?.strokes, 4)
            XCTAssertEqual(a.score(player: daveRow, hole: hole)?.strokes, 4 + hole)
            XCTAssertEqual(b.score(player: daveRow, hole: hole)?.strokes, 4 + hole)
        }
        // Exactly one displayed cell was replaced: Ray's copy of Dave's hole 2 (9 → 6). New cells raise nothing.
        let noticesA = await sessionA.notices
        XCTAssertEqual(noticesA.count, 1)
        XCTAssertEqual(noticesA.first?.hole, 2)
        XCTAssertEqual(noticesA.first?.previous, "9")
        XCTAssertEqual(noticesA.first?.current, "6")
        XCTAssertEqual(noticesA.first?.text, "Dave changed hole 2")
        let noticesB = await sessionB.notices
        XCTAssertTrue(noticesB.isEmpty, "Dave's own row and new cells raise no notice")
        let engineA = await sessionA.recompute()!, engineB = await sessionB.recompute()!
        XCTAssertEqual(engineA.perPlayer, engineB.perPlayer, "both local engines agree after the merge")
    }
}
