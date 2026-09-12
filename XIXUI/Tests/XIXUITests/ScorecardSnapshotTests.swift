// The Fraserview round through the shared renderer at screen and chat widths, with and without
// stickers, names and initials (Build Doc 2 step 4).
import Foundation
import XCTest
import XIXScoring
@testable import XIXUI

@MainActor
final class ScorecardSnapshotTests: XCTestCase {
    /// The reference round, straight from the engine's fixture, marks from the engine.
    static func fraserview(stickers: Bool, nameStyle: ScorecardModel.NameStyle) throws -> ScorecardModel {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("XIXScoring/Tests/XIXScoringTests/Fixtures/fraserview_2026-09-09.json")
        struct Envelope: Decodable { let input: RoundInput }
        let input = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url)).input
        let result = ScoringEngine.score(input)
        let names = ["ray": "Ray", "dave": "Dave", "mo": "Mo", "tess": "Tess"]
        let ids = Dictionary(uniqueKeysWithValues: input.players.map { ($0.id, UUID()) })
        let players = input.players.map { ScorecardModel.Player(id: ids[$0.id]!, name: names[$0.id.rawValue] ?? $0.id.rawValue) }

        var cells: [[ScorecardModel.Cell]] = []
        for (i, p) in input.players.enumerated() {
            let summary = result.perPlayer[p.id]!
            var row: [ScorecardModel.Cell] = []
            for h in 0..<input.holes {
                let score = input.scores[i][h]
                let text: String
                switch score { case .strokes(let n)?: text = String(n); case .pickedUp?: text = "X"; case nil: text = "" }
                let mark = ScorecardModel.Mark(rawValue: summary.marks[h].rawValue) ?? .none
                row.append(ScorecardModel.Cell(text: text, mark: mark))
            }
            cells.append(row)
        }
        if stickers {
            // Reactions the group actually threw in the design passes: YIKES on Dave's 7 at hole 7 (from Ray),
            // CLUTCH on Ray's eagle at 11 (from Tess), a stack on Mo's pick-up at 13, SIGNED on Dave's 8, DUCK IT on Dave's 12.
            cells[1][6].sticker = .init(key: "YIKES", senderInitials: "R")
            cells[0][10].sticker = .init(key: "CLUTCH", senderInitials: "T")
            cells[2][12].sticker = .init(key: "HAHAHA", senderInitials: "D", count: 3)
            cells[1][7].sticker = .init(key: "SIGNED", senderInitials: "D")
            cells[1][11].sticker = .init(key: "DUCK_IT", senderInitials: "D")
        }
        return ScorecardModel(
            courseName: "Fraserview", dateLabel: "9 Sep 2026", holes: input.holes, par: input.par, players: players, cells: cells,
            totals: input.players.map { result.perPlayer[$0.id]?.gross },
            liveCalloutHole: nil, nameStyle: nameStyle,
            strapline: "Skins · Ray 11 · Tess 4 · Mo 2 · Dave 1", joinLink: "xix.golf/r/FRSRVW")
    }

    private func check(_ name: String, width: CGFloat, stickers: Bool, nameStyle: ScorecardModel.NameStyle) throws {
        let model = try Self.fraserview(stickers: stickers, nameStyle: nameStyle)
        let image = try XCTUnwrap(ScorecardRenderer.image(model: model, width: width, scale: 2))
        XCTAssertEqual(image.width, Int(width * 2), "renders at the requested width")
        Snapshot.assert(image, named: name)
    }

    func testScreenNamesNoStickers() throws { try check("screen-names", width: XIXMetric.screenWidth, stickers: false, nameStyle: .names) }
    func testScreenNamesStickers() throws { try check("screen-names-stickers", width: XIXMetric.screenWidth, stickers: true, nameStyle: .names) }
    func testScreenInitialsStickers() throws { try check("screen-initials-stickers", width: XIXMetric.screenWidth, stickers: true, nameStyle: .initials) }
    func testChatNamesNoStickers() throws { try check("chat-names", width: XIXMetric.chatWidth, stickers: false, nameStyle: .names) }
    func testChatNamesStickers() throws { try check("chat-names-stickers", width: XIXMetric.chatWidth, stickers: true, nameStyle: .names) }
    func testChatInitialsStickers() throws { try check("chat-initials-stickers", width: XIXMetric.chatWidth, stickers: true, nameStyle: .initials) }

    func testLiveCalloutMarkAndPickUp() throws {
        var model = try Self.fraserview(stickers: false, nameStyle: .initials)
        model.liveCalloutHole = 12
        let image = try XCTUnwrap(ScorecardRenderer.image(model: model, width: XIXMetric.chatWidth, scale: 2))
        Snapshot.assert(image, named: "chat-initials-live-callout")
    }

    func testSameTreeOnScreenAndInExport() throws {
        // The export is the on-screen view rasterised: same model, same width → identical pixels.
        let model = try Self.fraserview(stickers: true, nameStyle: .names)
        let a = try XCTUnwrap(ScorecardRenderer.pngData(model: model, width: XIXMetric.chatWidth, scale: 2))
        let b = try XCTUnwrap(ScorecardRenderer.pngData(model: model, width: XIXMetric.chatWidth, scale: 2))
        XCTAssertEqual(a, b)
    }

    func testStickerPackLoads() {
        for key in StickerKey.allCases {
            XCTAssertNotNil(StickerImages.image(for: key), "\(key.rawValue).png")
        }
        XCTAssertNil(StickerImages.image(for: "NOT_A_STICKER"))
    }
}
