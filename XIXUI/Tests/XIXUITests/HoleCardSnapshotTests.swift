// The hole card on the Fraserview round (Build Doc 2 step 6): hole 12 with the live callout and no
// scores; hole 7 with two YIKES on Dave, sender chips, and the pad open; the par-5 hole 8 full with
// two stickers and its ink line.
import Foundation
import SwiftUI
import XCTest
import XIXScoring
@testable import XIXUI

@MainActor
final class HoleCardSnapshotTests: XCTestCase {
    struct Fixture {
        let input: RoundInput; let ids: [PlayerID: UUID]; let players: [ScorecardModel.Player]
        var ray: UUID { ids["ray"]! }; var dave: UUID { ids["dave"]! }; var mo: UUID { ids["mo"]! }; var tess: UUID { ids["tess"]! }
        func engineID(_ id: UUID) -> PlayerID { ids.first { $0.value == id }!.key }
    }

    static func fraserview() throws -> Fixture {
        let f = try GridSnapshotTests.fraserview()
        let names = ["ray": "Ray", "dave": "Dave", "mo": "Mo", "tess": "Tess"]
        let players = f.input.players.map { ScorecardModel.Player(id: f.ids[$0.id]!, name: names[$0.id.rawValue]!) }
        return Fixture(input: f.input, ids: f.ids, players: players)
    }

    static func scores(_ f: Fixture, through: Int) -> [GridScreenModel.ScoreInput] {
        var out: [GridScreenModel.ScoreInput] = []
        for (i, p) in f.input.players.enumerated() {
            for h in 0..<through {
                switch f.input.scores[i][h] {
                case .strokes(let n)?: out.append(.init(playerID: f.ids[p.id]!, hole: h + 1, strokes: n, pickedUp: false))
                case .pickedUp?: out.append(.init(playerID: f.ids[p.id]!, hole: h + 1, strokes: nil, pickedUp: true))
                case nil: break
                }
            }
        }
        return out
    }

    static func callouts(_ f: Fixture, responsesFor12: [UUID: String] = [:]) -> [HoleCardModel.CalloutInputModel] {
        [.init(id: UUID(uuidString: "99999999-9999-4999-8999-999999999991")!, hole: 8, kind: "target", callerID: f.ray, targetIDs: [f.dave], goal: "par", responses: [f.dave: "signed"], closed: true),
         .init(id: UUID(uuidString: "99999999-9999-4999-8999-999999999992")!, hole: 12, kind: "target", callerID: f.ray, targetIDs: [f.dave], goal: "par", responses: responsesFor12, closed: false)]
    }

    private func render(_ model: HoleCardModel) throws -> CGImage {
        // Sized to content: an open pad or a banner makes the card taller than a phone, and nothing may be clipped.
        let renderer = ImageRenderer(content: HoleCardView(model: model, width: XIXMetric.screenWidth, scrolls: false))
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: XIXMetric.screenWidth, height: nil)
        return try XCTUnwrap(renderer.cgImage)
    }

    func testHole12LiveCalloutNoScores() throws {
        let f = try Self.fraserview()
        let scores = Self.scores(f, through: 11)
        let result = ScoringEngine.score(GridSnapshotTests.truncated(f.input, through: 11))
        let model = HoleCardModel.build(hole: 12, holes: 18, par: f.input.par, strokeIndex: f.input.strokeIndex, yards: Array(repeating: nil, count: 18),
                                        players: f.players, engineID: f.engineID, scores: scores, stickers: [], callouts: Self.callouts(f),
                                        result: result, myPlayerID: f.dave, isOwner: false)
        XCTAssertTrue(model.rows.allSatisfy { $0.score.isEmpty })
        XCTAssertEqual(model.inPlay, "Nassau back nine · Skins · Stableford", "Ray took the skin on 11, so nothing carries into 12")
        XCTAssertEqual(model.callout?.detail, "BEAT PAR ON 12 · RAY → DAVE · EXPIRES ON SCORE")
        XCTAssertEqual(model.callout?.targets.map(\.state), [.pending])
        XCTAssertTrue(model.callout!.canRespond, "Dave is the target and has not answered")
        XCTAssertEqual(model.rows[1].canEdit, true, "Dave edits his own row")
        XCTAssertEqual(model.rows[0].canEdit, false, "but not Ray's")
        XCTAssertEqual(model.rows[0].standing, "Nassau 2&1 · AS · 3 up · Skins 6", "through 11: front won, back square, 3 up overall, six skins")
        Snapshot.assert(try render(model), named: "hole-12-live-callout")
    }

    func testHole7TwoYikesPadOpen() throws {
        let f = try Self.fraserview()
        let scores = Self.scores(f, through: 7)
        let result = ScoringEngine.score(GridSnapshotTests.truncated(f.input, through: 7))
        let stickers: [HoleCardModel.StickerInputModel] = [
            .init(id: UUID(), targetPlayerID: f.dave, senderPlayerID: f.ray, hole: 7, key: "YIKES", createdAt: 1),
            .init(id: UUID(), targetPlayerID: f.dave, senderPlayerID: f.tess, hole: 7, key: "YIKES", createdAt: 2)]
        var model = HoleCardModel.build(hole: 7, holes: 18, par: f.input.par, strokeIndex: f.input.strokeIndex, yards: Array(repeating: nil, count: 18),
                                        players: f.players, engineID: f.engineID, scores: scores, stickers: stickers, callouts: Self.callouts(f),
                                        result: result, myPlayerID: f.ray, isOwner: true,
                                        panel: .pad(.init(playerID: f.ray, playerName: "Ray", entered: 4)))
        XCTAssertEqual(model.rows[1].stickers.map(\.senderInitials), ["R", "T"])
        XCTAssertEqual(model.rows[1].score, "7")
        XCTAssertEqual(model.rows[1].mark, .filled)
        XCTAssertTrue(model.rows.allSatisfy(\.canEdit), "the owner edits any row")
        model.nudge = HoleCardModel.nudge(for: 7, par: 4, rows: model.rows, result: result)
        XCTAssertEqual(model.nudge, "Dave made 7. React?")
        Snapshot.assert(try render(model), named: "hole-7-yikes-pad")
    }

    func testHole8ParFiveFullWithStickers() throws {
        let f = try Self.fraserview()
        let scores = Self.scores(f, through: 18)
        let result = ScoringEngine.score(f.input)
        let stickers: [HoleCardModel.StickerInputModel] = [
            .init(id: UUID(), targetPlayerID: f.dave, senderPlayerID: f.dave, hole: 8, key: "SIGNED", createdAt: 1),
            .init(id: UUID(), targetPlayerID: f.mo, senderPlayerID: f.tess, hole: 8, key: "WASTED", createdAt: 2)]
        let model = HoleCardModel.build(hole: 8, holes: 18, par: f.input.par, strokeIndex: f.input.strokeIndex, yards: Array(repeating: nil, count: 18),
                                        players: f.players, engineID: f.engineID, scores: scores, stickers: stickers, callouts: Self.callouts(f),
                                        result: result, myPlayerID: f.tess, isOwner: false)
        XCTAssertEqual(model.par, 5)
        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(model.events, ["Halved. 1 carrying to 9."])
        XCTAssertEqual(model.callout?.detail, "BEAT PAR ON 8 · RAY → DAVE · CLOSED")
        XCTAssertEqual(model.callout?.targets.first?.state, .signed)
        XCTAssertFalse(model.callout!.canRespond)
        XCTAssertEqual(HoleCardModel.nudge(for: 8, par: 5, rows: model.rows, result: result), "Mo made 7. React?", "a blow-up (par+2) outranks the skins event")
        Snapshot.assert(try render(model), named: "hole-8-par5-full")
    }

    func testTrayOrderAndStripState() throws {
        XCTAssertEqual(StickerContext.blowUp.ordered.prefix(3).map(\.rawValue), ["YIKES", "WASTED", "HAHAHA"])
        XCTAssertEqual(StickerContext.blowUp.ordered.count, 12, "then the whole pack")
        XCTAssertEqual(StickerContext.ducked.ordered.prefix(2), [.duckIt, .hahaha])
        let f = try Self.fraserview()
        let model = HoleCardModel.build(hole: 12, holes: 18, par: f.input.par, strokeIndex: f.input.strokeIndex, yards: Array(repeating: nil, count: 18),
                                        players: f.players, engineID: f.engineID, scores: Self.scores(f, through: 11), stickers: [], callouts: [],
                                        result: nil, myPlayerID: nil, isOwner: false)
        XCTAssertEqual(model.strip[10].filled, 4)
        XCTAssertEqual(model.strip[11].filled, 0)
        XCTAssertEqual(model.inPlay, "")
    }
}
