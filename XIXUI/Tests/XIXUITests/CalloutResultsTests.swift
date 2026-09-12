// What the results screen says about each kind of callout (Build Doc 3 step 3). The engine resolves a
// small round with one of each; these pin the line the reader actually sees.
import Foundation
import XCTest
import XIXScoring
@testable import XIXUI

@MainActor
final class CalloutResultsTests: XCTestCase {
    let ray = UUID(uuidString: "77777777-7777-4777-8777-777777777771")!
    let dave = UUID(uuidString: "77777777-7777-4777-8777-777777777772")!
    let mo = UUID(uuidString: "77777777-7777-4777-8777-777777777773")!
    let tess = UUID(uuidString: "77777777-7777-4777-8777-777777777774")!
    let skins = UUID(uuidString: "88888888-8888-4888-8888-888888888881")!
    // The callouts carry the ids the database gives them, because the results screen matches its own
    // rows against the engine's by id.
    let c1 = UUID(uuidString: "99999999-9999-4999-8999-999999999991")!
    let c2 = UUID(uuidString: "99999999-9999-4999-8999-999999999992")!
    let c3 = UUID(uuidString: "99999999-9999-4999-8999-999999999993")!
    let c4 = UUID(uuidString: "99999999-9999-4999-8999-999999999994")!

    private func engineID(_ id: UUID) -> PlayerID { PlayerID(id.uuidString.lowercased()) }

    /// Four holes, four callouts, the same scores the data-layer test plays.
    private func round() -> (RoundResult, [ResultsModel.CalloutInput]) {
        let ids = [ray, dave, mo, tess]
        let scores: [[Int]] = [[5, 4, 5, 3],   // Ray
                               [4, 5, 4, 5],   // Dave
                               [5, 5, 4, 5],   // Mo
                               [4, 5, 3, 5]]   // Tess
        let input = RoundInput(
            holes: 4, par: Array(repeating: 4, count: 4), strokeIndex: Array(repeating: nil, count: 4),
            players: ids.map { PlayerInput(id: engineID($0), level: nil) },
            scores: scores.map { $0.map { .strokes($0) } },
            games: [GameInput(id: GameID(skins.uuidString.lowercased()), format: .skins, options: Options(), players: ids.map { engineID($0) })],
            callouts: [
                // Target: Dave signs and makes par, Mo ducks.
                CalloutInput(id: CalloutID(c1.uuidString.lowercased()), hole: 1, kind: .target, caller: engineID(ray), targets: [engineID(dave), engineID(mo)],
                             params: CalloutParams(goal: .par), responses: [engineID(dave): .signed, engineID(mo): .ducked]),
                // Duel: Ray's 4 against Dave's 5.
                CalloutInput(id: CalloutID(c2.uuidString.lowercased()), hole: 2, kind: .duel, caller: engineID(ray), targets: [engineID(dave)],
                             params: CalloutParams(), responses: [engineID(dave): .signed]),
                // Partner: Ray and Tess against Dave and Mo.
                CalloutInput(id: CalloutID(c3.uuidString.lowercased()), hole: 3, kind: .partner, caller: engineID(ray), targets: [engineID(dave), engineID(mo)],
                             params: CalloutParams(partner: engineID(tess)), responses: [engineID(dave): .signed, engineID(mo): .signed]),
                // Double: everyone signs, so hole 4 counts twice in Skins.
                CalloutInput(id: CalloutID(c4.uuidString.lowercased()), hole: 4, kind: .multiplier, caller: engineID(ray), targets: [engineID(dave), engineID(mo)],
                             params: CalloutParams(game: GameID(skins.uuidString.lowercased())),
                             responses: [engineID(dave): .signed, engineID(mo): .signed]),
            ])
        let inputs: [ResultsModel.CalloutInput] = [
            .init(id: c1, hole: 1, kind: "target", callerID: ray, targetIDs: [dave, mo], goal: "par"),
            .init(id: c2, hole: 2, kind: "duel", callerID: ray, targetIDs: [dave], goal: nil),
            .init(id: c3, hole: 3, kind: "partner", callerID: ray, targetIDs: [dave, mo], goal: nil),
            .init(id: c4, hole: 4, kind: "multiplier", callerID: ray, targetIDs: [dave, mo], goal: nil, gameName: "Skins"),
        ]
        return (ScoringEngine.score(input), inputs)
    }

    private func model(viewer: UUID?) -> ResultsModel {
        let (result, inputs) = round()
        let players = [(ray, "Ray"), (dave, "Dave"), (mo, "Mo"), (tess, "Tess")].map { ScorecardModel.Player(id: $0.0, name: $0.1) }
        return ResultsModel.build(courseName: "Test Links", dateLabel: "12 Sep 2026", par: Array(repeating: 4, count: 4),
                                  players: players, engineID: { PlayerID($0.uuidString.lowercased()) },
                                  result: result, callouts: inputs, stickers: [], myPlayerID: viewer)
    }

    func testEachKindSaysWhatHappened() {
        let m = model(viewer: ray)
        XCTAssertEqual(m.callouts.count, 4)
        let byTitle = Dictionary(uniqueKeysWithValues: m.callouts.map { ($0.title, $0) })

        let target = try! XCTUnwrap(byTitle["Beat par on 1"])
        XCTAssertEqual(target.sub, "Ray → Dave, Mo")
        XCTAssertEqual(target.mark, "DAVE MADE IT · MO DUCKED", "one signed and hit it, the other ducked")

        let duel = try! XCTUnwrap(byTitle["Duel on 2"])
        XCTAssertEqual(duel.mark, "CALLED IT", "the caller took it")

        let partner = try! XCTUnwrap(byTitle["Partner pick on 3"])
        XCTAssertEqual(partner.mark, "CALLED IT · WITH RAY & TESS")

        let double = try! XCTUnwrap(byTitle["Double on 4 · Skins"])
        XCTAssertEqual(double.mark, "DOUBLED", "a double has no winner to name; it just counted twice")
    }

    func testADuckedCalloutAndALoneWolfReadCorrectly() {
        let (result, inputs) = round()
        var ducked = result
        // Every target ducked: nothing was played, and the screen says so plainly.
        ducked.callouts[0].status = .ducked
        ducked.callouts[0].ducked = [PlayerID(dave.uuidString.lowercased()), PlayerID(mo.uuidString.lowercased())]
        ducked.callouts[0].hit = nil
        ducked.callouts[0].winner = nil
        var lone = ducked
        lone.callouts[2].loneWolf = true

        let players = [(ray, "Ray"), (dave, "Dave"), (mo, "Mo"), (tess, "Tess")].map { ScorecardModel.Player(id: $0.0, name: $0.1) }
        let m = ResultsModel.build(courseName: "Test Links", dateLabel: "12 Sep 2026", par: Array(repeating: 4, count: 4),
                                   players: players, engineID: { PlayerID($0.uuidString.lowercased()) },
                                   result: lone, callouts: inputs, stickers: [], myPlayerID: ray)
        XCTAssertEqual(m.callouts.first { $0.title == "Beat par on 1" }?.mark, "DUCKED")
        XCTAssertEqual(m.callouts.first { $0.title == "Partner pick on 3" }?.mark, "CALLED IT · WITH RAY & TESS · LONE WOLF")
    }
}
