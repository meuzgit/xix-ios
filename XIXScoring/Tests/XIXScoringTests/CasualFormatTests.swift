import XCTest
@testable import XIXScoring

final class CasualFormatTests: XCTestCase {
    func testFixture() throws {
        try FixtureRunner.run("casual_first")
    }

    private func input(par: [Int?] = [4, 4, 4, 4, 4, 4], players: [PlayerInput], scores: [[HoleScore?]], format: Format) -> RoundInput {
        RoundInput(holes: par.count, par: par, strokeIndex: [], players: players, scores: scores,
                   games: [GameInput(id: "g", format: format, players: players.map(\.id))])
    }

    func testParDependentFormatsAreUnavailableWithoutPar() {
        let players = [PlayerInput(id: "a", extras: PlayerExtras(priorAverage: 30)), PlayerInput(id: "b", extras: PlayerExtras(priorAverage: 30))]
        for format in [Format.fewestBlowUps, .bogeyGolf, .mostPars, .firstToFive, .worstHole] {
            let r = ScoringEngine.score(input(par: [4, nil, 4], players: players, scores: [[4, 4, 4], [4, 4, 4]], format: format))
            XCTAssertTrue(r.games[0].outcome?.isUnavailable ?? false, "\(format)")
        }
        let avg = ScoringEngine.score(input(par: [4, nil, 4], players: players, scores: [[4, 4, 4], [4, 4, 4]], format: .beatYourAverage))
        XCTAssertEqual(avg.games[0].outcome, .tied(["a", "b"]), "Beat Your Average does not need par")
    }

    func testBeatYourAverageNeedsPriorAverageForEveryone() {
        let players = [PlayerInput(id: "a", extras: PlayerExtras(priorAverage: 30)), PlayerInput(id: "b")]
        let r = ScoringEngine.score(input(players: players, scores: [Array(repeating: 4, count: 6), Array(repeating: 4, count: 6)], format: .beatYourAverage))
        XCTAssertEqual(r.games[0].outcome, .unavailable(reason: "Beat Your Average needs a prior average for every player; missing: b"))
    }

    func testFirstToFiveDecidesEarlyBreaksTiesByEarlierHoleAndReportsGenuineTies() {
        let players = ["a", "b"].map { PlayerInput(id: PlayerID($0), level: 5) }
        // a reaches five on hole 5; the round is not complete but the game is decided.
        var a: [HoleScore?] = [4, 4, 4, 4, 4, nil]
        var b: [HoleScore?] = [5, 5, 5, 5, 5, nil]
        let early = ScoringEngine.score(input(players: players, scores: [a, b], format: .firstToFive))
        XCTAssertEqual(early.status, .inProgress(throughHole: 5))
        XCTAssertEqual(early.games[0].outcome, .winner("a"))
        XCTAssertEqual(early.games[0].display["a"], "First to Five at 5")
        // Nobody reaches five: both have 3, a's third came on hole 3, b's on hole 5 → a.
        a = [4, 4, 4, 5, 5, 5]; b = [4, 5, 4, 5, 4, 5]
        let most = ScoringEngine.score(input(players: players, scores: [a, b], format: .firstToFive))
        XCTAssertEqual(most.games[0].outcome, .winner("a"))
        XCTAssertTrue(most.medals.isEmpty, "five_pars needs five reached")
        // Same count reached on the same hole → tied.
        let tie = ScoringEngine.score(input(players: players, scores: [b, b], format: .firstToFive))
        XCTAssertEqual(tie.games[0].outcome, .tied(["a", "b"]))
        XCTAssertEqual(tie.rivalPoints, ["a": 2, "b": 2])
    }

    func testWorstHoleCountsPickUpAndSharesTies() {
        let players = ["a", "b"].map { PlayerInput(id: PlayerID($0), level: 5) }
        let r = ScoringEngine.score(input(par: [5, 4], players: players, scores: [[.pickedUp, 4], [4, 9]], format: .worstHole))
        XCTAssertEqual(r.games[0].outcome, .tied(["a", "b"]), "a's pick-up is +5 on a par 5; b's 9 is +5")
        if case .worstHole(let d)? = r.games.first?.detail {
            XCTAssertEqual(d.perPlayer["a"], WorstHole(hole: 1, overPar: 5))
            XCTAssertEqual(d.worstOverPar, 5)
        } else { XCTFail() }
        XCTAssertEqual(r.games[0].display["b"], "Worst Hole +5 (2)")
    }

    func testMedalsShareOnTiesAndNeedTheCondition() {
        // Tied Beat Your Average with negative improvement → no beat_average medal.
        let players = [PlayerInput(id: "a", level: 5, extras: PlayerExtras(priorAverage: 20)), PlayerInput(id: "b", level: 5, extras: PlayerExtras(priorAverage: 20))]
        let worse = ScoringEngine.score(input(players: players, scores: [Array(repeating: 4, count: 6), Array(repeating: 4, count: 6)], format: .beatYourAverage))
        XCTAssertEqual(worse.games[0].outcome, .tied(["a", "b"]))
        XCTAssertTrue(worse.medals.isEmpty)
        // Tied Fewest Blow-Ups where both have one blow-up → no no_blowups medal; zero each → both.
        let one = ScoringEngine.score(input(players: players, scores: [[7, 4, 4, 4, 4, 4], [4, 7, 4, 4, 4, 4]], format: .fewestBlowUps))
        XCTAssertTrue(one.medals.isEmpty)
        let none = ScoringEngine.score(input(players: players, scores: [Array(repeating: 5, count: 6), Array(repeating: 5, count: 6)], format: .fewestBlowUps))
        XCTAssertEqual(none.medals.map(\.profile), ["a", "b"])
    }
}
