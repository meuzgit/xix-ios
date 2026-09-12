// The step 5 screens, drawn from plain models: the cabinet and its empty state, a medal's context card
// with the round it came from, the rivalry, and both boards with the pending row.
import Foundation
import SwiftUI
import XCTest
import XIXScoring
@testable import XIXUI

@MainActor
final class CabinetSnapshotTests: XCTestCase {
    private func id(_ n: Int) -> UUID { UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-00000000000\(n)")! }

    private func patch(_ key: MedalKey, context: String) -> MedalPatchModel {
        let p = key.patch
        return MedalPatchModel(id: key.rawValue, shape: p.shape, accent: key.accent, top: p.top, bottom: p.bottom,
                               name: p.name, context: context)
    }

    private func render<V: View>(_ view: V, width: CGFloat = XIXMetric.screenWidth) throws -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        return try XCTUnwrap(renderer.cgImage)
    }

    // MARK: Cabinet

    private var cabinet: CabinetModel {
        CabinetModel(owner: "Ray", total: 5, seasons: [
            .init(label: "2026 SEASON", medals: [
                .init(id: id(1), patch: patch(.nassauFront, context: "vs Dave · Fraserview"), when: "9 Sep · vs Dave"),
                .init(id: id(2), patch: patch(.skinsTwo, context: "Fraserview"), when: "9 Sep · Fraserview"),
                .init(id: id(3), patch: patch(.calloutCalledIt, context: "vs Dave"), when: "9 Sep · vs Dave"),
                .init(id: id(4), patch: patch(.fivePars, context: "McCleery"), when: "2 Sep · McCleery"),
            ]),
            .init(label: "2025 SEASON", medals: [
                .init(id: id(5), patch: patch(.skinsFour, context: "Fraserview"), when: "11 Oct · Fraserview"),
            ]),
        ])
    }

    func testCabinet() throws {
        Snapshot.assert(try render(CabinetScreen(model: cabinet, scrolls: false)), named: "cabinet")
    }

    func testCabinetEmpty() throws {
        let empty = CabinetModel(owner: "Ray", total: 0, seasons: [])
        XCTAssertTrue(empty.isEmpty)
        Snapshot.assert(try render(CabinetScreen(model: empty, scrolls: false)), named: "cabinet-empty")
    }

    func testMedalContextCard() throws {
        let f = try GridSnapshotTests.fraserview()
        let names = ["ray": "Ray", "dave": "Dave", "mo": "Mo", "tess": "Tess"]
        let players = f.input.players.map { ScorecardModel.Player(id: f.ids[$0.id]!, name: names[$0.id.rawValue]!) }
        let back = Dictionary(uniqueKeysWithValues: f.ids.map { ($0.value, $0.key) })
        var scores: [GridScreenModel.ScoreInput] = []
        for (i, p) in f.input.players.enumerated() {
            for h in 0..<f.input.holes {
                if case .strokes(let n)? = f.input.scores[i][h] {
                    scores.append(.init(playerID: f.ids[p.id]!, hole: h + 1, strokes: n, pickedUp: false))
                }
            }
        }
        let grid = GridScreenModel.build(courseName: "Fraserview", dateLabel: "9 Sep 2026", holes: f.input.holes, par: f.input.par,
                                         players: players, engineID: { back[$0]! }, scores: scores, stickers: [],
                                         liveCalloutHoles: [], result: f.result, nameStyle: .names, selectedPill: nil)
        let card = MedalContextCard(patch: patch(.skinsTwo, context: "vs Dave · Fraserview · 9 Sep 2026"),
                                    how: "Holes 6 and 14 · Fraserview · 9 Sep 2026",
                                    scorecard: grid.scorecard, scrolls: false)
        Snapshot.assert(try render(card), named: "medal-context-card")
    }

    // MARK: Rivalry

    func testRivalry() throws {
        let model = RivalryModel(
            me: "Ray", them: "Dave", myWins: 4, theirWins: 3, rounds: 7,
            streak: "RAY ON A 3-ROUND STREAK",
            stats: [("MEDALS", "5"), ("THEY SIGNED", "4"), ("THEY DUCKED", "2")],
            medals: [patch(.nassauFront, context: "vs Dave"), patch(.skinsTwo, context: "vs Dave"), patch(.calloutDuckedNothing, context: "vs Dave")],
            lastFive: [
                .init(id: id(1), course: "Fraserview", date: "9 Sep", outcome: "W", line: "78 to 84", stickers: ["YIKES", "HAHAHA"]),
                .init(id: id(2), course: "McCleery", date: "2 Sep", outcome: "W", line: "80 to 82", stickers: ["CLUTCH"]),
                .init(id: id(3), course: "Langara", date: "24 Aug", outcome: "W", line: "79 to 88", stickers: []),
                .init(id: id(4), course: "Fraserview", date: "17 Aug", outcome: "L", line: "86 to 81", stickers: ["SANDBAGGER"]),
                .init(id: id(5), course: "McCleery", date: "10 Aug", outcome: "H", line: "83 to 83", stickers: []),
            ])
        XCTAssertEqual(model.myWins + model.theirWins, 7)
        Snapshot.assert(try render(RivalryScreen(model: model, scrolls: false)), named: "rivalry")
    }

    // MARK: Rankings

    private func rows() -> [RankingsModel.Row] {
        [.init(id: id(1), rank: 1, name: "Tess Okafor", initials: "TO", sub: "11 rounds · Level 6", value: "182", movement: 1, isMe: false),
         .init(id: id(2), rank: 2, name: "Ray", initials: "R", sub: "9 rounds · Level 5", value: "168", movement: -1, isMe: true),
         .init(id: id(3), rank: 3, name: "Dave", initials: "D", sub: "7 rounds · Level 4", value: "151", movement: 0, isMe: false)]
    }

    func testGlobalBoardWithPendingRow() throws {
        let model = RankingsModel(
            scope: "Everyone", isCrew: false, metric: "Stableford", period: "ALL TIME", rows: rows(),
            pending: [.init(id: id(9), line: "Fraserview · 13 Sep · Mo 88",
                            waiting: "Waiting on one other player. Counts automatically in 41 hours.", frozen: false)],
            footnote: "Results count once another player in the round confirms them, or after 48 hours.")
        Snapshot.assert(try render(RankingsScreen(model: model, metrics: ["Stableford", "Birdies", "Rounds", "Rival Points"], scrolls: false)),
                        named: "rankings-global")
    }

    func testCrewBoardWithAFrozenResult() throws {
        let model = RankingsModel(
            scope: "Sunday Foursome", isCrew: true, crewPrivateNote: true, metric: "Rival Points", period: "ALL TIME",
            rows: Array(rows().prefix(2)),
            pending: [.init(id: id(9), line: "Fraserview · 13 Sep · Mo 88",
                            waiting: "This result is on hold. Both of you get the card to re-check; whoever fixes a cell, the other confirms.",
                            frozen: true)],
            footnote: "Results count once another player in the round confirms them, or after 48 hours.")
        Snapshot.assert(try render(RankingsScreen(model: model, metrics: ["Stableford", "Birdies", "Rounds", "Rival Points"], scrolls: false)),
                        named: "rankings-crew-frozen")
    }

    func testCrewCreationSteps() throws {
        let name = Binding.constant("Sunday Foursome")
        Snapshot.assert(try render(CrewNameStep(name: name, suggestions: ["Sunday Foursome", "The Regulars"], onNext: {})),
                        named: "crew-name")
        let people = CrewPeopleStep(
            crewName: "Sunday Foursome",
            added: [.init(id: id(1), name: "Dave", sub: "7 rounds together")],
            recent: [.init(id: id(2), name: "Mo", sub: "3 rounds"), .init(id: id(3), name: "Tess", sub: "5 rounds")],
            link: "xix.golf/c/8K2M", onAdd: { _ in }, onRemove: { _ in }, onDone: {})
        Snapshot.assert(try render(people), named: "crew-people")
    }
}
