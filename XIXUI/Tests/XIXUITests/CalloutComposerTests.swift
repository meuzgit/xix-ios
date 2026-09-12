// The composer refuses exactly what `create_callout` refuses, so a player never meets a round trip that
// was never going to work (Build Doc 3 step 3). The rules live in xix.create_callout; these pin the
// client's copy of them against that function.
import Foundation
import SwiftUI
import XCTest
@testable import XIXUI

@MainActor
final class CalloutComposerTests: XCTestCase {
    let ray = UUID(uuidString: "77777777-7777-4777-8777-777777777771")!
    let dave = UUID(uuidString: "77777777-7777-4777-8777-777777777772")!
    let mo = UUID(uuidString: "77777777-7777-4777-8777-777777777773")!
    let tess = UUID(uuidString: "77777777-7777-4777-8777-777777777774")!
    let skins = UUID(uuidString: "88888888-8888-4888-8888-888888888881")!

    func model(scored: Set<UUID> = [], games: Bool = true) -> CalloutComposerModel {
        CalloutComposerModel(
            hole: 12, par: 4,
            players: [.init(id: ray, name: "Ray", initials: "R"), .init(id: dave, name: "Dave", initials: "D"),
                      .init(id: mo, name: "Mo", initials: "M"), .init(id: tess, name: "Tess", initials: "T")],
            games: games ? [.init(id: skins, name: "Skins")] : [],
            callerID: ray, scored: scored)
    }

    func testATargetNeedsSomebodyToAimAt() {
        let m = model()
        var draft = CalloutDraft()
        XCTAssertEqual(m.problem(with: draft), "Pick who you are calling out.")
        draft.targets = [dave]
        XCTAssertNil(m.problem(with: draft))
    }

    func testTheCallerIsNeverATarget() {
        let m = model()
        var draft = CalloutDraft()
        draft.targets = [ray]
        XCTAssertEqual(m.problem(with: draft), "Pick who you are calling out.", "aiming at yourself is aiming at nobody")
        XCTAssertFalse(m.others.contains { $0.id == ray }, "and you are not offered as a target")
    }

    func testADuelIsOneOnOne() {
        let m = model()
        var draft = CalloutDraft()
        draft.kind = .duel
        draft.targets = [dave, mo]
        XCTAssertEqual(m.problem(with: draft), "A duel is one on one. Pick one player.")
        draft.targets = [dave]
        XCTAssertNil(m.problem(with: draft))
    }

    func testADoubleNeedsAGameAndSaysSoWhenThereIsNone() {
        var draft = CalloutDraft()
        draft.kind = .multiplier
        draft.targets = [dave]
        XCTAssertEqual(model(games: false).problem(with: draft), "Doubling needs a game in this round.")
        XCTAssertEqual(model().problem(with: draft), "Pick the game this hole doubles.")
        draft.game = skins
        XCTAssertNil(model().problem(with: draft))
        XCTAssertEqual(model().params(for: draft), ["game_id": skins.uuidString.lowercased()],
                       "ids go down lowercased, as the engine compares them, and the factor is the engine's default")
    }

    func testAPartnerCannotAlsoBeOnTheOtherSide() {
        let m = model()
        var draft = CalloutDraft()
        draft.kind = .partner
        draft.targets = [dave, mo]
        draft.partner = dave
        XCTAssertEqual(m.problem(with: draft), "Your partner cannot be on the other side.")
        draft.partner = tess
        XCTAssertNil(m.problem(with: draft))
        XCTAssertEqual(m.params(for: draft), ["partner_id": tess.uuidString.lowercased()])
        draft.partner = nil
        XCTAssertNil(m.problem(with: draft), "on your own is allowed")
        XCTAssertEqual(m.params(for: draft), [:], "and carries no partner")
    }

    func testAScoredHoleIsClosedToCallouts() {
        var draft = CalloutDraft()
        draft.targets = [dave, mo]
        XCTAssertEqual(model(scored: [dave]).problem(with: draft), "Dave has already scored this hole.")
        XCTAssertEqual(model(scored: [dave, mo]).problem(with: draft), "Dave and Mo have already scored this hole.")
        XCTAssertEqual(model(scored: [ray]).problem(with: draft), "Ray has already scored this hole.", "the caller counts too")
        XCTAssertNil(model(scored: [tess]).problem(with: draft), "somebody outside the callout does not close it")
    }

    func testTheGoalGoesDownInTheEnginesWords() {
        let m = model()
        var draft = CalloutDraft()
        draft.targets = [dave]
        XCTAssertEqual(m.params(for: draft), ["goal": "par"])
        draft.goal = .birdie
        XCTAssertEqual(m.params(for: draft), ["goal": "birdie"])
        draft.goal = .strokes(3)
        XCTAssertEqual(m.params(for: draft), ["goal": "3"])
    }

    func testThePreviewIsTheBannerTheOthersWillSee() {
        let m = model()
        var draft = CalloutDraft()
        draft.targets = [dave]
        XCTAssertEqual(m.preview(draft).detail, "BEAT PAR ON 12 · RAY → DAVE · EXPIRES ON SCORE")
        draft.goal = .birdie
        XCTAssertEqual(m.preview(draft).detail, "BIRDIE ON 12 · RAY → DAVE · EXPIRES ON SCORE")
        draft.kind = .duel
        XCTAssertEqual(m.preview(draft).detail, "DUEL ON 12 · RAY → DAVE · EXPIRES ON SCORE")
        draft.kind = .partner
        draft.partner = tess
        XCTAssertEqual(m.preview(draft).detail, "PARTNER PICK ON 12 · WITH TESS · RAY → DAVE · EXPIRES ON SCORE")
        draft.partner = nil
        XCTAssertEqual(m.preview(draft).detail, "ON MY OWN ON 12 · RAY → DAVE · EXPIRES ON SCORE")
        draft.kind = .multiplier
        draft.game = skins
        XCTAssertEqual(m.preview(draft).detail, "SKINS DOUBLE ON 12 · RAY → DAVE · EXPIRES ON SCORE")
        XCTAssertFalse(m.preview(draft).canRespond, "a preview is not answerable")
    }

    func testComposerSnapshot() throws {
        let view = CalloutComposer(model: model(), onSend: { _ in }, onClose: {}, scrolls: false)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: XIXMetric.screenWidth, height: nil)
        Snapshot.assert(try XCTUnwrap(renderer.cgImage), named: "callout-composer")
    }
}
