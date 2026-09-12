// Build Doc 3 step 2, the data half: a sticker thrown by one player, opened by the other, and the
// sender's session told. The UI test drives the same path through two simulators; this one pins the
// contract and the timing without a screen.
import XCTest
@testable import XIXData
@testable import XIXModels

final class StickerPlayedTests: XCTestCase {
    var ray: XIXClient!
    var dave: XIXClient!
    var bundle: RoundBundle!
    var sessionA: RoundSession!
    var sessionB: RoundSession!

    override func setUp() async throws {
        try XCTSkipIf(LocalSupabase.isRemote, "runs against the local stack")
        ray = try await LocalSupabase.client(as: LocalSupabase.ray, email: "ray@privaterelay.appleid.com", label: "ray-\(name)")
        dave = try await LocalSupabase.client(as: LocalSupabase.dave, email: "dave@privaterelay.appleid.com", label: "dave-\(name)")
        bundle = try await LocalSupabase.freshRound(owner: ray)
        let daveRow = try XCTUnwrap(bundle.players.first { $0.displayName == "Dave" })
        try await RoundRepository(client: dave).claimRow(roundID: bundle.round.id, playerID: daveRow.id)
        sessionA = RoundSession(client: ray, roundID: bundle.round.id, connectivity: Connectivity(startMonitoring: false))
        sessionB = RoundSession(client: dave, roundID: bundle.round.id, connectivity: Connectivity(startMonitoring: false))
        try await sessionA.start()
        try await sessionB.start()
        try await Task.sleep(for: .milliseconds(500))
    }

    override func tearDown() async throws {
        await sessionA?.stop()
        await sessionB?.stop()
    }

    private var daveRow: UUID { bundle.players.first { $0.displayName == "Dave" }!.id }

    func testOpeningAStickerTellsTheSender() async throws {
        // Ray watches for the moment Dave opens it.
        let told = expectation(description: "Ray is told the sticker was opened")
        var announced: RoundSession.StickerPlayed?
        let events = await sessionA.events()
        let watching = Task {
            for await event in events {
                if case .stickerPlayed(let played) = event {
                    announced = played
                    told.fulfill()
                    return
                }
            }
        }

        // Ray throws a YIKES at Dave's hole 7.
        await sessionA.sendSticker(hole: 7, targetPlayerID: daveRow, stickerKey: "YIKES")
        await LocalSupabase.waitUntil(10, "Dave's session to receive the sticker") {
            await self.sessionB.currentState().stickers.contains { $0.sticker_key == "YIKES" && $0.hole == 7 }
        }
        // One sticker, not two: the optimistic row the send wrote locally is replaced by the server's,
        // which mints its own id (the card used to carry both).
        await LocalSupabase.waitUntil(5, "the sender's own copy to settle") {
            await self.sessionA.currentState().stickers.filter { $0.sticker_key == "YIKES" }.count == 1
        }
        let mine = await sessionA.currentState().stickers.filter { $0.sticker_key == "YIKES" }
        XCTAssertEqual(mine.count, 1, "the thrower sees the sticker once")
        let theirs = await sessionB.currentState().stickers.filter { $0.sticker_key == "YIKES" }
        XCTAssertEqual(theirs.count, 1, "and so does the target")
        let sticker = try XCTUnwrap(theirs.first)
        XCTAssertNil(sticker.played_at, "it arrives unopened")
        XCTAssertEqual(sticker.pack_key, "base", "the base pack is the free one")

        // Dave opens it.
        let opened = Date()
        await sessionB.markPlayed(stickerID: sticker.id)
        let localState = await sessionB.currentState()
        XCTAssertNotNil(localState.stickers.first { $0.id == sticker.id }?.played_at, "his own card marks it played at once")

        await fulfillment(of: [told], timeout: 10)
        watching.cancel()
        let played = try XCTUnwrap(announced)
        XCTAssertEqual(played.stickerKey, "YIKES")
        XCTAssertEqual(played.hole, 7)
        XCTAssertEqual(played.openedBy, "Dave")
        XCTAssertEqual(played.text, "Dave opened your YIKES")
        print("[acceptance] sender told \(String(format: "%.2f", Date().timeIntervalSince(opened)))s after the tap")

        // And the played stamp is on the server, not only on Dave's phone.
        await LocalSupabase.waitUntil(10, "Ray's copy to carry played_at") {
            await self.sessionA.currentState().stickers.first { $0.id == sticker.id }?.played_at != nil
        }
    }

    func testOpeningIsIdempotentAndOnlyTheTargetMarksIt() async throws {
        await sessionA.sendSticker(hole: 3, targetPlayerID: daveRow, stickerKey: "HAHAHA")
        await LocalSupabase.waitUntil(10, "the sticker to reach Dave") {
            await self.sessionB.currentState().stickers.contains { $0.sticker_key == "HAHAHA" }
        }
        let onHisCard = await sessionB.currentState().stickers
        let sticker = try XCTUnwrap(onHisCard.first { $0.sticker_key == "HAHAHA" })

        await sessionB.markPlayed(stickerID: sticker.id)
        await LocalSupabase.waitUntil(10, "the played stamp to land") {
            await self.sessionA.currentState().stickers.first { $0.id == sticker.id }?.played_at != nil
        }
        let first = await sessionA.currentState().stickers.first { $0.id == sticker.id }?.played_at

        // A second tap changes nothing.
        await sessionB.markPlayed(stickerID: sticker.id)
        try await Task.sleep(for: .milliseconds(600))
        let second = await sessionB.currentState().stickers.first { $0.id == sticker.id }?.played_at
        XCTAssertEqual(first, second, "opening it twice keeps the first stamp")

        // The sender cannot mark a sticker played: RLS lets only the target's row through, so Ray's
        // update matches nothing. PostgREST reports no error for an update that touches no rows, so the
        // proof is that the stamp does not move.
        await sessionA.sendSticker(hole: 4, targetPlayerID: daveRow, stickerKey: "SNAKE")
        await LocalSupabase.waitUntil(10, "the second sticker to reach Dave") {
            await self.sessionB.currentState().stickers.contains { $0.sticker_key == "SNAKE" }
        }
        let afterSecond = await sessionB.currentState().stickers
        let theirs = try XCTUnwrap(afterSecond.first { $0.sticker_key == "SNAKE" })
        try await PlayRepository(client: ray).markStickerPlayed(stickerID: theirs.id)
        try await Task.sleep(for: .milliseconds(800))
        await sessionB.resync()
        let stillUnopened = await sessionB.currentState().stickers.first { $0.id == theirs.id }?.played_at
        XCTAssertNil(stillUnopened, "the sender cannot open a sticker on the target's behalf")
    }
}
