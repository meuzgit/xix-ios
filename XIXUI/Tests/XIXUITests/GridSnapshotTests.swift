// The grid screen on the Fraserview round (the seeded round's source of truth) in Skins mode and in
// Gross mode, plus the current-hole rule (Build Doc 2 step 5).
import Foundation
import SwiftUI
import XCTest
import XIXScoring
@testable import XIXUI

@MainActor
final class GridSnapshotTests: XCTestCase {
    struct Fixture { let input: RoundInput; let result: RoundResult; let ids: [PlayerID: UUID] }

    static func fraserview() throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("XIXScoring/Tests/XIXScoringTests/Fixtures/fraserview_2026-09-09.json")
        struct Envelope: Decodable { let input: RoundInput }
        let input = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url)).input
        let ids = Dictionary(uniqueKeysWithValues: input.players.enumerated().map { ($1.id, UUID(uuidString: "77777777-7777-4777-8777-77777777777\($0 + 1)")!) })
        return Fixture(input: input, result: ScoringEngine.score(input), ids: ids)
    }

    static func model(stickers: Bool = true, selected: String?, scoresThrough: Int? = nil) throws -> GridScreenModel {
        let f = try fraserview()
        let names = ["ray": "Ray", "dave": "Dave", "mo": "Mo", "tess": "Tess"]
        let players = f.input.players.map { ScorecardModel.Player(id: f.ids[$0.id]!, name: names[$0.id.rawValue]!) }
        let back = Dictionary(uniqueKeysWithValues: f.ids.map { ($0.value, $0.key) })
        var scores: [GridScreenModel.ScoreInput] = []
        for (i, p) in f.input.players.enumerated() {
            for h in 0..<f.input.holes where scoresThrough == nil || h < scoresThrough! {
                switch f.input.scores[i][h] {
                case .strokes(let n)?: scores.append(.init(playerID: f.ids[p.id]!, hole: h + 1, strokes: n, pickedUp: false))
                case .pickedUp?: scores.append(.init(playerID: f.ids[p.id]!, hole: h + 1, strokes: nil, pickedUp: true))
                case nil: break
                }
            }
        }
        var pins: [GridScreenModel.StickerInput] = []
        if stickers {
            let ray = f.ids["ray"]!, dave = f.ids["dave"]!, mo = f.ids["mo"]!, tess = f.ids["tess"]!
            pins = [.init(targetPlayerID: dave, senderPlayerID: ray, hole: 7, key: "YIKES", createdAt: 1),
                    .init(targetPlayerID: dave, senderPlayerID: dave, hole: 8, key: "SIGNED", createdAt: 2),
                    .init(targetPlayerID: ray, senderPlayerID: tess, hole: 11, key: "CLUTCH", createdAt: 3),
                    .init(targetPlayerID: dave, senderPlayerID: dave, hole: 12, key: "DUCK_IT", createdAt: 4),
                    .init(targetPlayerID: mo, senderPlayerID: ray, hole: 13, key: "WASTED", createdAt: 5),
                    .init(targetPlayerID: mo, senderPlayerID: tess, hole: 13, key: "YIKES", createdAt: 6),
                    .init(targetPlayerID: mo, senderPlayerID: dave, hole: 13, key: "HAHAHA", createdAt: 7)]
        }
        let result = scoresThrough == nil ? f.result : ScoringEngine.score(truncated(f.input, through: scoresThrough!))
        return GridScreenModel.build(courseName: "Fraserview", dateLabel: "9 Sep 2026", holes: f.input.holes, par: f.input.par,
                                     players: players, engineID: { back[$0]! }, scores: scores, stickers: pins,
                                     liveCalloutHoles: scoresThrough != nil ? [scoresThrough! + 1] : [],
                                     result: result, nameStyle: .names, selectedPill: selected, joinLink: "xix.golf/r/FRSRVW")
    }

    static func truncated(_ input: RoundInput, through: Int) -> RoundInput {
        var i = input
        i.scores = i.scores.map { row in row.enumerated().map { $0.offset < through ? $0.element : nil } }
        return i
    }

    private func render(_ model: GridScreenModel, selected: String?) throws -> CGImage {
        let view = GridScreenContent(model: model, selectedPill: .constant(selected), width: XIXMetric.screenWidth) { _ in }
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: XIXMetric.screenWidth, height: nil)
        return try XCTUnwrap(renderer.cgImage)
    }

    func testSkinsMode() throws {
        let model = try Self.model(selected: nil)
        XCTAssertEqual(model.pills.map(\.label), ["NASSAU", "SKINS", "STABLEFORD", "GROSS"], "active games first, in setup order, Gross last")
        let skins = model.pills.first { $0.label == "SKINS" }!
        XCTAssertEqual(skins.rows.map { "\($0.name) \($0.value)" }, ["Ray 11", "Tess 4", "Mo 2", "Dave 1"])
        XCTAssertNil(model.currentHole, "every cell is in")
        var m = model; m.selectedPill = skins.id
        Snapshot.assert(try render(m, selected: skins.id), named: "grid-skins")
    }

    func testGrossMode() throws {
        let model = try Self.model(selected: "gross")
        let gross = model.selected!
        XCTAssertEqual(gross.label, "GROSS")
        XCTAssertEqual(gross.rows.map { "\($0.name) \($0.value)" }, ["Ray +6", "Tess +6", "Dave +12", "Mo +16"])
        XCTAssertEqual(gross.rows.map(\.rank), [1, 1, 3, 4])
        Snapshot.assert(try render(model, selected: "gross"), named: "grid-gross")
    }

    func testNassauRowsAndDefaultPill() throws {
        let model = try Self.model(selected: nil)
        XCTAssertEqual(model.selected?.label, "NASSAU", "the first active game is the default mode")
        XCTAssertEqual(model.selected?.rows.map(\.value), ["2&1 · AS · 5&4", "L 2&1 · AS · L 5&4"], "compact front · back · 18 from each side")
    }

    func testCurrentHoleIsFirstWithAnyEmptyScoreAndLiveMark() throws {
        let model = try Self.model(stickers: false, selected: nil, scoresThrough: 11)
        XCTAssertEqual(model.currentHole, 12)
        XCTAssertEqual(model.scorecard.liveCalloutHole, 12)
        XCTAssertEqual(model.scorecard.cells[0][11].text, "", "hole 12 is empty")
        XCTAssertEqual(model.scorecard.totals[0], 48, "gross so far: 39 out, then 5 and 4")
        var m = model; m.notice = "Dave changed hole 6"
        Snapshot.assert(try render(m, selected: nil), named: "grid-in-progress-notice")
    }

    func testStackedStickersShowTopAndCount() throws {
        let model = try Self.model(selected: nil)
        let mo = 2
        XCTAssertEqual(model.scorecard.cells[mo][12].sticker, .init(key: "HAHAHA", senderInitials: "D", count: 3))
        XCTAssertEqual(model.scorecard.cells[1][6].sticker?.key, "YIKES")
    }
}
