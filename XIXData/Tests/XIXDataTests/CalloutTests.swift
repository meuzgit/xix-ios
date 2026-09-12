// Build Doc 3 step 3: all four kinds of callout created through `create_callout` with the composer's
// own params, answered per target by two other players, and resolved by the engine. Three clients on
// one round, against the local stack.
import Supabase
import XCTest
@testable import XIXData
@testable import XIXModels
import XIXScoring

final class CalloutTests: XCTestCase {
    var ray: XIXClient!
    var dave: XIXClient!
    var mo: XIXClient!
    var bundle: RoundBundle!
    var session: RoundSession!
    var games: [GameRow] = []

    override func setUp() async throws {
        try XCTSkipIf(LocalSupabase.isRemote, "runs against the local stack")
        ray = try await LocalSupabase.client(as: LocalSupabase.ray, email: "ray@privaterelay.appleid.com", label: "ray-\(name)")
        dave = try await LocalSupabase.client(as: LocalSupabase.dave, email: "dave@privaterelay.appleid.com", label: "dave-\(name)")
        mo = try await LocalSupabase.client(as: LocalSupabase.mo, email: "mo@privaterelay.appleid.com", label: "mo-\(name)")
        bundle = try await LocalSupabase.freshRound(owner: ray, guestNames: ["Dave", "Mo", "Tess"])
        let rows = Dictionary(uniqueKeysWithValues: bundle.players.map { ($0.displayName, $0.id) })
        try await RoundRepository(client: dave).claimRow(roundID: bundle.round.id, playerID: rows["Dave"]!)
        try await RoundRepository(client: mo).claimRow(roundID: bundle.round.id, playerID: rows["Mo"]!)
        games = try await RoundRepository(client: ray).setGames(roundID: bundle.round.id, games: [
            GameDraft(format: "skins", players: bundle.players.map(\.id))
        ])
        session = RoundSession(client: ray, roundID: bundle.round.id, connectivity: Connectivity(startMonitoring: false))
        try await session.start()
        try await Task.sleep(for: .milliseconds(400))
    }

    override func tearDown() async throws {
        await session?.stop()
    }

    private func row(_ name: String) -> UUID { bundle.players.first { $0.displayName == name }!.id }
    private func engineID(_ name: String) -> PlayerID { PlayerID(row(name).uuidString.lowercased()) }

    /// The composer's own params, so the test exercises what the app sends.
    private func params(_ draft: CalloutDraftShim) -> [String: AnyJSON] {
        draft.params.mapValues { AnyJSON.string($0) }
    }

    struct CalloutDraftShim { var params: [String: String] }

    func testAllFourKindsResolveTheWayTheEngineSaysTheyDo() async throws {
        let play = PlayRepository(client: ray)
        let dRepo = PlayRepository(client: dave), mRepo = PlayRepository(client: mo)

        // 1. Target on hole 1: Ray calls Dave and Mo to make par. Dave signs, Mo ducks.
        let target = try await play.createCallout(roundID: bundle.round.id, hole: 1, kind: "target",
                                                  targets: [row("Dave"), row("Mo")],
                                                  params: params(.init(params: ["goal": "par"])))
        try await dRepo.respondCallout(calloutID: target.id, action: .signed)
        try await mRepo.respondCallout(calloutID: target.id, action: .ducked)

        // 2. Duel on hole 2: Ray against Dave. Dave signs.
        let duel = try await play.createCallout(roundID: bundle.round.id, hole: 2, kind: "duel",
                                                targets: [row("Dave")], params: [:])
        try await dRepo.respondCallout(calloutID: duel.id, action: .signed)

        // 3. Partner on hole 3: Ray with Tess against Dave and Mo. Both sign.
        let partner = try await play.createCallout(roundID: bundle.round.id, hole: 3, kind: "partner",
                                                   targets: [row("Dave"), row("Mo")],
                                                   params: params(.init(params: ["partner_id": row("Tess").uuidString.lowercased()])))
        try await dRepo.respondCallout(calloutID: partner.id, action: .signed)
        try await mRepo.respondCallout(calloutID: partner.id, action: .signed)

        // 4. Double on hole 4: the Skins hole counts twice. Every target must sign.
        let skins = try XCTUnwrap(games.first)
        let double = try await play.createCallout(roundID: bundle.round.id, hole: 4, kind: "multiplier",
                                                  targets: [row("Dave"), row("Mo")],
                                                  params: params(.init(params: ["game_id": skins.id.uuidString.lowercased()])))
        try await dRepo.respondCallout(calloutID: double.id, action: .signed)
        try await mRepo.respondCallout(calloutID: double.id, action: .signed)

        // Now the scores. Par is 4 on every hole here.
        // Hole 1: Dave makes par (hits the target), Mo makes 5, Ray 5.
        await session.enterScore(playerID: row("Ray"), hole: 1, strokes: 5, pickedUp: false)
        await session.enterScore(playerID: row("Dave"), hole: 1, strokes: 4, pickedUp: false)
        await session.enterScore(playerID: row("Mo"), hole: 1, strokes: 5, pickedUp: false)
        await session.enterScore(playerID: row("Tess"), hole: 1, strokes: 4, pickedUp: false)
        // Hole 2: Ray 4 beats Dave 5.
        await session.enterScore(playerID: row("Ray"), hole: 2, strokes: 4, pickedUp: false)
        await session.enterScore(playerID: row("Dave"), hole: 2, strokes: 5, pickedUp: false)
        await session.enterScore(playerID: row("Mo"), hole: 2, strokes: 5, pickedUp: false)
        await session.enterScore(playerID: row("Tess"), hole: 2, strokes: 5, pickedUp: false)
        // Hole 3: Ray 5, Tess 3 (their best is 3) against Dave 4, Mo 4 → the caller's side takes it.
        await session.enterScore(playerID: row("Ray"), hole: 3, strokes: 5, pickedUp: false)
        await session.enterScore(playerID: row("Tess"), hole: 3, strokes: 3, pickedUp: false)
        await session.enterScore(playerID: row("Dave"), hole: 3, strokes: 4, pickedUp: false)
        await session.enterScore(playerID: row("Mo"), hole: 3, strokes: 4, pickedUp: false)
        // Hole 4: Ray alone on 3 takes the skin, and it counts double.
        await session.enterScore(playerID: row("Ray"), hole: 4, strokes: 3, pickedUp: false)
        await session.enterScore(playerID: row("Dave"), hole: 4, strokes: 5, pickedUp: false)
        await session.enterScore(playerID: row("Mo"), hole: 4, strokes: 5, pickedUp: false)
        await session.enterScore(playerID: row("Tess"), hole: 4, strokes: 5, pickedUp: false)

        await LocalSupabase.waitUntil(20, "every score acknowledged") { await self.session.pendingWrites() == 0 }
        await session.resync()
        let recomputed = await session.recompute()
        let result = try XCTUnwrap(recomputed)
        XCTAssertEqual(result.callouts.count, 4, "four callouts, one of each kind")

        func callout(_ id: UUID) throws -> CalloutResult {
            try XCTUnwrap(result.callouts.first { $0.calloutID.rawValue == id.uuidString.lowercased() })
        }

        // Target: Dave signed and made par; Mo ducked and takes no part.
        let t = try callout(target.id)
        XCTAssertEqual(t.kind, .target)
        XCTAssertEqual(t.status, .resolved)
        XCTAssertEqual(t.hit, [engineID("Dave")])
        XCTAssertEqual(t.winner, .player(engineID("Dave")))
        XCTAssertEqual(t.ducked, [engineID("Mo")])
        XCTAssertEqual(t.perTarget.first { $0.player == engineID("Dave") }?.response, .signed)
        XCTAssertEqual(t.perTarget.first { $0.player == engineID("Mo") }?.response, .ducked)

        // Duel: low score on the hole.
        let d = try callout(duel.id)
        XCTAssertEqual(d.kind, .duel)
        XCTAssertEqual(d.status, .resolved)
        XCTAssertEqual(d.winner, .player(engineID("Ray")), "Ray's 4 beat Dave's 5")

        // Partner: best ball, the caller's side.
        let p = try callout(partner.id)
        XCTAssertEqual(p.kind, .partner)
        XCTAssertEqual(p.status, .resolved)
        XCTAssertEqual(p.winner, .players([engineID("Ray"), engineID("Tess")]), "Tess's 3 carried the side")
        XCTAssertEqual(p.loneWolf, false)

        // Double: signed by everyone, so the Skins hole counted twice.
        let m = try callout(double.id)
        XCTAssertEqual(m.kind, .multiplier)
        XCTAssertEqual(m.status, .resolved)
        let skinsGame = try XCTUnwrap(result.games.first { $0.format == .skins })
        guard case .skins(let detail) = skinsGame.detail else { return XCTFail("skins detail") }
        XCTAssertEqual(detail.perHole[3].winner, engineID("Ray"), "Ray alone on 3 took hole 4")
        XCTAssertEqual(detail.perHole[3].skins, 2, "and it counted double because every target signed")
    }

    func testAScoredHoleRefusesACalloutAndTheSessionSaysSo() async throws {
        await session.enterScore(playerID: row("Dave"), hole: 7, strokes: 4, pickedUp: false)
        await LocalSupabase.waitUntil(10, "the score to land") { await self.session.pendingWrites() == 0 }

        // Straight at the RPC: the server is the one that refuses it.
        do {
            _ = try await PlayRepository(client: ray).createCallout(roundID: bundle.round.id, hole: 7, kind: "target",
                                                                    targets: [row("Dave")], params: ["goal": .string("par")])
            XCTFail("a scored hole is closed to callouts")
        } catch let error as PostgrestError {
            XCTAssertTrue(error.message.contains("already scored hole 7"), "got: \(error.message)")
        }

        // And through the session, where it surfaces as the toast the card shows.
        let rejected = expectation(description: "the card is told why")
        var message: String?
        let events = await session.events()
        let watching = Task {
            for await event in events {
                if case .rejected(_, let m) = event { message = m; rejected.fulfill(); return }
            }
        }
        await session.createCallout(hole: 7, kind: "target", targets: [row("Dave")], params: ["goal": .string("par")])
        await fulfillment(of: [rejected], timeout: 15)
        watching.cancel()
        XCTAssertEqual(message?.contains("already scored hole 7"), true, "got: \(message ?? "nothing")")
    }

    /// Build Doc 1 B.6: on a Partner callout the named partner is on the caller's side, is not a target,
    /// and is never asked to respond. This pins all three — what was stored, what the server allows her
    /// to do, and what the engine made of her.
    func testThePartnerIsNotATargetAndCannotRespond() async throws {
        let tess = try await LocalSupabase.client(as: LocalSupabase.tess, email: "tess@privaterelay.appleid.com", label: "tess-\(name)")
        try await RoundRepository(client: tess).claimRow(roundID: bundle.round.id, playerID: row("Tess"))

        let callout = try await PlayRepository(client: ray).createCallout(
            roundID: bundle.round.id, hole: 6, kind: "partner",
            targets: [row("Dave"), row("Mo")],
            params: ["partner_id": .string(row("Tess").uuidString.lowercased())])

        // Stored: the rest, and only the rest. Not the caller, not the partner.
        XCTAssertEqual(Set(callout.targetIds), [row("Dave"), row("Mo")])
        XCTAssertFalse(callout.targetIds.contains(row("Tess")), "the partner is not a target")
        XCTAssertFalse(callout.targetIds.contains(row("Ray")), "and neither is the caller")

        // Asked: only the two of them. The partner's own client is refused by the server.
        do {
            _ = try await PlayRepository(client: tess).respondCallout(calloutID: callout.id, action: .signed)
            XCTFail("the partner was never asked and cannot answer")
        } catch let error as PostgrestError {
            XCTAssertTrue(error.message.contains("was not sent to you"), "got: \(error.message)")
        }
        try await PlayRepository(client: dave).respondCallout(calloutID: callout.id, action: .signed)
        try await PlayRepository(client: mo).respondCallout(calloutID: callout.id, action: .signed)

        // Resolved: Tess's 3 carries the caller's side, without her ever signing anything.
        await session.enterScore(playerID: row("Ray"), hole: 6, strokes: 5, pickedUp: false)
        await session.enterScore(playerID: row("Tess"), hole: 6, strokes: 3, pickedUp: false)
        await session.enterScore(playerID: row("Dave"), hole: 6, strokes: 4, pickedUp: false)
        await session.enterScore(playerID: row("Mo"), hole: 6, strokes: 4, pickedUp: false)
        await LocalSupabase.waitUntil(20, "hole 6 acknowledged") { await self.session.pendingWrites() == 0 }
        await session.resync()
        let recomputed = await session.recompute()
        let result = try XCTUnwrap(recomputed)
        let resolved = try XCTUnwrap(result.callouts.first { $0.calloutID.rawValue == callout.id.uuidString.lowercased() })

        XCTAssertEqual(Set(resolved.targets), [engineID("Dave"), engineID("Mo")], "the engine sees two targets")
        XCTAssertFalse(resolved.perTarget.contains { $0.player == engineID("Tess") }, "and no response of any kind from the partner")
        XCTAssertEqual(resolved.winner, .players([engineID("Ray"), engineID("Tess")]), "she still wins it with him")
        XCTAssertEqual(resolved.loneWolf, false)
    }

    func testADuelWithTwoTargetsIsRefusedByTheServerToo() async throws {
        do {
            _ = try await PlayRepository(client: ray).createCallout(roundID: bundle.round.id, hole: 9, kind: "duel",
                                                                    targets: [row("Dave"), row("Mo")], params: [:])
            XCTFail("a duel has exactly one target")
        } catch let error as PostgrestError {
            XCTAssertTrue(error.message.contains("duel has exactly one target"), "got: \(error.message)")
        }
    }
}
