import XCTest
@testable import XIXScoring

final class CalloutTests: XCTestCase {
    /// Three players, two holes, par 4/4. Hole 1 scores: a 4, b 5, c 3.
    private func input(scores: [[HoleScore?]] = [[4, 4], [5, 4], [3, 4]], par: [Int?] = [4, 4],
                       callouts: [CalloutInput]) -> RoundInput {
        RoundInput(holes: 2, par: par, strokeIndex: [],
                   players: ["a", "b", "c"].map { PlayerInput(id: PlayerID($0), level: 5) },
                   scores: scores, callouts: callouts)
    }

    /// Every target signs unless `responses` says otherwise.
    private func callout(kind: CalloutKind, caller: PlayerID = "a", targets: [PlayerID] = ["b", "c"],
                         params: CalloutParams = CalloutParams(goal: .par), responses: [PlayerID: CalloutResponse]? = nil,
                         hole: Int = 1) -> CalloutInput {
        let r = responses ?? Dictionary(uniqueKeysWithValues: targets.filter { $0 != caller }.map { ($0, CalloutResponse.signed) })
        return CalloutInput(id: "c", hole: hole, kind: kind, caller: caller, targets: targets, params: params, responses: r)
    }

    func testTargetHitAndMiss() {
        let hit = ScoringEngine.score(input(callouts: [callout(kind: .target)])).callouts[0]
        XCTAssertEqual(hit.status, .resolved)
        XCTAssertEqual(hit.hit, ["c"])
        XCTAssertEqual(hit.winner, .player("c"))
        XCTAssertEqual(hit.perTarget, [CalloutTargetResult(player: "b", response: .signed, hit: false),
                                       CalloutTargetResult(player: "c", response: .signed, hit: true)])
        let miss = ScoringEngine.score(input(callouts: [callout(kind: .target, targets: ["b"])])).callouts[0]
        XCTAssertEqual(miss.hit, [])
        XCTAssertEqual(miss.winner, .player("a"), "nobody hit → caller wins")
        let birdie = ScoringEngine.score(input(callouts: [callout(kind: .target, params: CalloutParams(goal: .birdie))])).callouts[0]
        XCTAssertEqual(birdie.hit, ["c"])
        let number = ScoringEngine.score(input(callouts: [callout(kind: .target, params: CalloutParams(goal: .strokes(5)))])).callouts[0]
        XCTAssertEqual(number.winner, .players(["b", "c"]))
    }

    func testCallerNeverCountsAsATarget() {
        // B.8.10: a "crew" callout lists everyone including the caller; a's own 4 does not hit.
        let c = ScoringEngine.score(input(scores: [[4, 4], [5, 4], [5, 4]],
                                          callouts: [callout(kind: .target, targets: ["a", "b", "c"])])).callouts[0]
        XCTAssertEqual(c.targets, ["b", "c"])
        XCTAssertEqual(c.hit, [])
        XCTAssertEqual(c.winner, .player("a"))
    }

    func testPerTargetResponsesSignedDuckedAndUnanswered() {
        // B.8.10 as written in v1.1: c signs, b ducks. Only c can hit; b's score is irrelevant.
        let mixed = ScoringEngine.score(input(scores: [[5, 4], [3, 4], [4, 4]],
                                              callouts: [callout(kind: .target, responses: ["c": .signed, "b": .ducked])])).callouts[0]
        XCTAssertEqual(mixed.status, .resolved)
        XCTAssertEqual(mixed.hit, ["c"])
        XCTAssertEqual(mixed.winner, .player("c"))
        XCTAssertEqual(mixed.ducked, ["b"])
        XCTAssertEqual(mixed.duckedBy, "b")
        XCTAssertEqual(mixed.signedTargets, ["c"])
        // Unanswered target expires once a participant scores; the callout still resolves among the signed.
        let partial = ScoringEngine.score(input(scores: [[4, 4], [3, 4], [5, 4]],
                                                callouts: [callout(kind: .target, responses: ["c": .signed])])).callouts[0]
        XCTAssertEqual(partial.expired, ["b"])
        XCTAssertEqual(partial.perTarget.map(\.response), [.expired, .signed])
        XCTAssertEqual(partial.winner, .player("a"), "b's birdie does not count: b never signed")
    }

    func testOpenExpiresOnlyWhenAParticipantScores() {
        // B.8.11: c scores hole 1 but is not a participant → still open; then b scores → expired.
        let open = ScoringEngine.score(input(scores: [[nil, nil], [nil, nil], [3, nil]],
                                             callouts: [callout(kind: .target, targets: ["b"], responses: [:])])).callouts[0]
        XCTAssertEqual(open.status, .open)
        XCTAssertEqual(open.perTarget, [CalloutTargetResult(player: "b", response: .pending)])
        let expired = ScoringEngine.score(input(scores: [[nil, nil], [5, nil], [3, nil]],
                                                callouts: [callout(kind: .target, targets: ["b"], responses: [:])])).callouts[0]
        XCTAssertEqual(expired.status, .expired)
        XCTAssertEqual(expired.expired, ["b"])
        XCTAssertNil(expired.winner)
    }

    func testSignedWaitsForEveryParticipantThenResolves() {
        let pending = ScoringEngine.score(input(scores: [[4, nil], [nil, nil], [3, nil]],
                                                callouts: [callout(kind: .target, targets: ["b"])])).callouts[0]
        XCTAssertEqual(pending.status, .live)
        XCTAssertNil(pending.winner)
        // A score from a non-participant after signing changes nothing.
        let resolved = ScoringEngine.score(input(scores: [[4, nil], [5, nil], [3, nil]],
                                                 callouts: [callout(kind: .target, targets: ["b"])])).callouts[0]
        XCTAssertEqual(resolved.status, .resolved)
    }

    func testDuckedIsRecordedWithNoResult() {
        let r = ScoringEngine.score(input(callouts: [callout(kind: .target, targets: ["b"], responses: ["b": .ducked])]))
        XCTAssertEqual(r.callouts[0].status, .ducked)
        XCTAssertEqual(r.callouts[0].duckedBy, "b")
        XCTAssertNil(r.callouts[0].winner)
        XCTAssertEqual(r.rivalPoints, ["a": 0, "b": 0, "c": 0])
        XCTAssertTrue(r.medals.isEmpty)
        // Everyone ducks a crew callout → ducked; nobody signs but one is unanswered → expired once scored.
        let all = ScoringEngine.score(input(callouts: [callout(kind: .target, responses: ["b": .ducked, "c": .ducked])])).callouts[0]
        XCTAssertEqual(all.status, .ducked)
        let some = ScoringEngine.score(input(callouts: [callout(kind: .target, responses: ["b": .ducked])])).callouts[0]
        XCTAssertEqual(some.status, .expired)
        XCTAssertEqual(some.expired, ["c"])
    }

    func testDuel() {
        let win = ScoringEngine.score(input(callouts: [callout(kind: .duel, targets: ["b"], params: CalloutParams())]))
        XCTAssertEqual(win.callouts[0].winner, .player("a"))
        XCTAssertEqual(win.medals, [MedalAward(profile: "a", key: .calloutDuel, opponent: "b", holes: [1])])
        XCTAssertEqual(win.rivalPoints["a"], 3)
        let lose = ScoringEngine.score(input(callouts: [callout(kind: .duel, targets: ["c"], params: CalloutParams())]))
        XCTAssertEqual(lose.callouts[0].winner, .player("c"))
        XCTAssertEqual(lose.medals.first?.opponent, "a")
        let tie = ScoringEngine.score(input(scores: [[4, 4], [4, 4], [3, 4]],
                                            callouts: [callout(kind: .duel, targets: ["b"], params: CalloutParams())]))
        XCTAssertEqual(tie.callouts[0].winner, .halved)
        XCTAssertEqual(tie.rivalPoints["a"], 2, "1.5 each, rounded")
        XCTAssertTrue(tie.medals.isEmpty)
        let bad = ScoringEngine.score(input(callouts: [callout(kind: .duel, targets: ["b", "c"], params: CalloutParams())]))
        XCTAssertEqual(bad.callouts[0].status, .live)
        XCTAssertEqual(bad.callouts[0].reason, "duel needs exactly one target")
    }

    func testPartnerLoneWolfAndWithPartner() {
        // Lone a (4) vs best ball of b (5), c (3): the rest win as a side.
        let lost = ScoringEngine.score(input(callouts: [callout(kind: .partner, params: CalloutParams())]))
        XCTAssertEqual(lost.callouts[0].winner, .players(["b", "c"]))
        XCTAssertEqual(lost.rivalPoints, ["a": 0, "b": 3, "c": 3])
        XCTAssertEqual(lost.callouts[0].loneWolf, false)
        // Lone a (3) vs b (5), c (4): lone wolf wins.
        let lone = ScoringEngine.score(input(scores: [[3, 4], [5, 4], [4, 4]],
                                             callouts: [callout(kind: .partner, params: CalloutParams())]))
        XCTAssertEqual(lone.callouts[0].winner, .player("a"))
        XCTAssertEqual(lone.callouts[0].loneWolf, true)
        XCTAssertEqual(lone.medals, [MedalAward(profile: "a", key: .calloutLoneWolf, holes: [1])])
        XCTAssertEqual(lone.rivalPoints["a"], 3)
        // a + partner c (3) vs b (5): side wins, no lone wolf.
        let pair = ScoringEngine.score(input(callouts: [callout(kind: .partner, targets: ["b"], params: CalloutParams(partner: "c"))]))
        XCTAssertEqual(pair.callouts[0].winner, .players(["a", "c"]))
        XCTAssertEqual(pair.callouts[0].loneWolf, false)
        XCTAssertEqual(pair.rivalPoints, ["a": 3, "b": 0, "c": 3])
        XCTAssertTrue(pair.medals.isEmpty)
        // Only the signed rest play: c ducks → a (4) v b (5) → a wins as a lone wolf.
        let ducked = ScoringEngine.score(input(callouts: [callout(kind: .partner, params: CalloutParams(), responses: ["b": .signed, "c": .ducked])]))
        XCTAssertEqual(ducked.callouts[0].winner, .player("a"))
        XCTAssertEqual(ducked.callouts[0].loneWolf, true)
    }

    func testMultiplierNeedsEveryTargetToSign() {
        let game = GameInput(id: "s", format: .skins, players: ["a", "b", "c"])
        var i = input(callouts: [callout(kind: .multiplier, params: CalloutParams(game: "s", factor: 2))])
        i.games = [game]
        let r = ScoringEngine.score(i)
        XCTAssertEqual(r.callouts[0].status, .resolved)
        XCTAssertNil(r.callouts[0].winner)
        if case .skins(let d)? = r.games.first?.detail { XCTAssertEqual(d.perHole[0].skins, 2) } else { XCTFail() }
        XCTAssertEqual(r.rivalPoints["a"], 0)
        var half = input(callouts: [callout(kind: .multiplier, params: CalloutParams(game: "s", factor: 2), responses: ["b": .signed])])
        half.games = [game]
        let h = ScoringEngine.score(half)
        XCTAssertEqual(h.callouts[0].status, .expired)
        if case .skins(let d)? = h.games.first?.detail { XCTAssertEqual(d.perHole[0].skins, 1, "no factor without every signature") } else { XCTFail() }
    }

    func testTargetWithUnknownParStaysLiveWithReason() {
        let r = ScoringEngine.score(input(par: [nil, 4], callouts: [callout(kind: .target, targets: ["b"])]))
        XCTAssertEqual(r.callouts[0].status, .live)
        XCTAssertEqual(r.callouts[0].reason, "par unknown on hole 1")
        XCTAssertNil(r.callouts[0].winner)
    }

    func testDuckedNothingMedalNeedsTwoPersonallySigned() {
        let two = [callout(kind: .target, targets: ["b"]),
                   CalloutInput(id: "d", hole: 2, kind: .target, caller: "c", targets: ["b"],
                                params: CalloutParams(goal: .par), responses: ["b": .signed])]
        let r = ScoringEngine.score(input(callouts: two))
        XCTAssertTrue(r.medals.contains(MedalAward(profile: "b", key: .calloutDuckedNothing)))
        var one = two; one[1].responses["b"] = .ducked
        XCTAssertFalse(ScoringEngine.score(input(callouts: one)).medals.contains { $0.key == .calloutDuckedNothing })
        XCTAssertFalse(ScoringEngine.score(input(callouts: [two[0]])).medals.contains { $0.key == .calloutDuckedNothing })
        // A crew callout signed by b but not by c counts for b only.
        let crew = [callout(kind: .target, responses: ["b": .signed]), CalloutInput(id: "e", hole: 2, kind: .target, caller: "a", targets: ["b", "c"],
                                                                                    params: CalloutParams(goal: .par), responses: ["b": .signed, "c": .signed])]
        XCTAssertEqual(ScoringEngine.score(input(callouts: crew)).medals.filter { $0.key == .calloutDuckedNothing }.map(\.profile), ["b"])
    }
}
