// The results screen on the Fraserview round (Build Doc 3 step 1): Ray's view with medals, the three
// games, the callouts and the stickers he received; and a guest's result-link confirm card.
import Foundation
import SwiftUI
import XCTest
import XIXScoring
@testable import XIXUI

@MainActor
final class ResultsSnapshotTests: XCTestCase {
    static func model(viewer: String?, confirm: ResultsModel.ConfirmCard? = nil) throws -> ResultsModel {
        let f = try GridSnapshotTests.fraserview()
        let names = ["ray": "Ray", "dave": "Dave", "mo": "Mo", "tess": "Tess"]
        let players = f.input.players.map { ScorecardModel.Player(id: f.ids[$0.id]!, name: names[$0.id.rawValue]!) }
        let back = Dictionary(uniqueKeysWithValues: f.ids.map { ($0.value, $0.key) })
        let callouts = f.input.callouts.map { c in
            ResultsModel.CalloutInput(id: UUID(uuidString: c.id.rawValue) ?? UUID(), hole: c.hole, kind: c.kind.rawValue, callerID: f.ids[c.caller]!,
                                      targetIDs: c.targets.map { f.ids[$0]! }, goal: nil)
        }
        let ray = f.ids["ray"]!, tess = f.ids["tess"]!, dave = f.ids["dave"]!
        let stickers: [HoleCardModel.StickerInputModel] = [
            .init(id: UUID(), targetPlayerID: ray, senderPlayerID: tess, hole: 11, key: "CLUTCH", createdAt: 1),
            .init(id: UUID(), targetPlayerID: ray, senderPlayerID: dave, hole: 15, key: "SANDBAGGER", createdAt: 2),
        ]
        return ResultsModel.build(courseName: "Fraserview", dateLabel: "9 Sep 2026", par: f.input.par, players: players, engineID: { back[$0]! },
                                  result: f.result, callouts: callouts, stickers: stickers, myPlayerID: viewer.map { f.ids[PlayerID($0)]! }, confirm: confirm)
    }

    private func render(_ model: ResultsModel) throws -> CGImage {
        let renderer = ImageRenderer(content: ResultsScreen(model: model, width: XIXMetric.screenWidth, scrolls: false))
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: XIXMetric.screenWidth, height: nil)
        return try XCTUnwrap(renderer.cgImage)
    }

    func testRaysResults() throws {
        let m = try Self.model(viewer: "ray")
        XCTAssertEqual(m.title, "Your results")
        XCTAssertEqual(m.headline, "78")
        XCTAssertEqual(m.headlineSub, "+6 GROSS")
        XCTAssertEqual(m.games.map(\.name), ["Nassau", "Skins", "Stableford"])
        XCTAssertFalse(m.medals.isEmpty, "a complete round awards medals")
        XCTAssertEqual(m.medals.first?.context.contains("Ray"), false, "the viewer's own medals carry no name")
        XCTAssertEqual(m.stickersReceived, ["CLUTCH", "SANDBAGGER"])
        XCTAssertFalse(m.pending)
        Snapshot.assert(try render(m), named: "results-ray")
    }

    func testGuestConfirmCard() throws {
        let m = try Self.model(viewer: "tess", confirm: .pending(owner: "Ray", medals: 1))
        XCTAssertEqual(m.confirm?.label, "YOUR SCORES, KEPT BY RAY")
        Snapshot.assert(try render(m), named: "results-guest-confirm")
    }

    func testEveryMedalHasAPatch() {
        for key in MedalKey.allCases {
            XCTAssertFalse(key.patch.top.isEmpty, key.rawValue)
            XCTAssertFalse(key.patch.bottom.isEmpty, key.rawValue)
        }
    }
}
