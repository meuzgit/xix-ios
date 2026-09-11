import XCTest
@testable import XIXScoring

final class NormalisationTests: XCTestCase {
    private func round(holes: Int = 3, par: [Int?] = [4, 5, 3], strokeIndex: [Int?] = [nil, nil, nil],
                       players: [PlayerInput], scores: [[HoleScore?]]) -> NormalisedRound {
        NormalisedRound(RoundInput(holes: holes, par: par, strokeIndex: strokeIndex, players: players, scores: scores))
    }

    func testPickedUpIsDoubleParOrTenWithoutPar() {
        XCTAssertEqual(NormalisedRound.effectiveStrokes(.pickedUp, par: 5), 10)
        XCTAssertEqual(NormalisedRound.effectiveStrokes(.pickedUp, par: 3), 6)
        XCTAssertEqual(NormalisedRound.effectiveStrokes(.pickedUp, par: nil), 10)
        XCTAssertEqual(NormalisedRound.effectiveStrokes(.strokes(7), par: nil), 7)
    }

    func testMarks() {
        XCTAssertEqual(NormalisedRound.mark(for: .strokes(2), par: 4), .circle)
        XCTAssertEqual(NormalisedRound.mark(for: .strokes(3), par: 4), .circle)
        XCTAssertEqual(NormalisedRound.mark(for: .strokes(4), par: 4), .none)
        XCTAssertEqual(NormalisedRound.mark(for: .strokes(5), par: 4), .square)
        XCTAssertEqual(NormalisedRound.mark(for: .strokes(6), par: 4), .filled)
        XCTAssertEqual(NormalisedRound.mark(for: .strokes(9), par: 4), .filled)
        XCTAssertEqual(NormalisedRound.mark(for: .pickedUp, par: 4), .x)
        XCTAssertEqual(NormalisedRound.mark(for: .pickedUp, par: nil), .none, "no marks when par is nil")
        XCTAssertEqual(NormalisedRound.mark(for: .strokes(9), par: nil), .none)
    }

    func testLevelToStrokes() {
        XCTAssertEqual(NormalisedRound.strokes(forLevel: 10), 0)
        XCTAssertEqual(NormalisedRound.strokes(forLevel: 1), 22)
        XCTAssertEqual(NormalisedRound.strokes(forLevel: 5), 12)
        XCTAssertEqual(NormalisedRound.strokes(forLevel: 0), 24, "clamped at 24")
        XCTAssertEqual(NormalisedRound.strokes(forLevel: 12), 0, "clamped at 0")
        XCTAssertEqual(NormalisedRound.handicapStrokes(for: PlayerInput(id: "a", level: 5, index: 7.4)), 7, "index overrides Level")
        XCTAssertNil(NormalisedRound.handicapStrokes(for: PlayerInput(id: "a")))
    }

    func testAllocationByStrokeIndexThenEvenly() {
        let bySI = NormalisedRound.allocator(holes: 3, strokeIndex: [3, 1, 2])
        XCTAssertEqual(bySI(1), [0, 1, 0])
        XCTAssertEqual(bySI(2), [0, 1, 1])
        XCTAssertEqual(bySI(4), [1, 2, 1], "wraps to the hardest hole again")
        let even = NormalisedRound.allocator(holes: 3, strokeIndex: [3, nil, 2])
        XCTAssertEqual(even(2), [1, 1, 0], "evenly from hole 1 when any stroke index is unknown")
        XCTAssertEqual(even(0), [0, 0, 0])
    }

    func testNetStrokesAndSummary() {
        let r = round(strokeIndex: [2, 1, 3],
                      players: [PlayerInput(id: "a", level: 9.5)],   // round(0.5 × 2.4) = 1 stroke
                      scores: [[.strokes(5), .strokes(6), .strokes(3)]])
        XCTAssertEqual(r.handicapStrokes, [1])
        XCTAssertEqual(r.net[0], [5, 5, 3])
        let s = r.summary(seat: 0)
        XCTAssertEqual(s.gross, 14)
        XCTAssertEqual(s.net, 13)
        XCTAssertEqual(s.toPar, 2)
        XCTAssertEqual(s.holesEntered, 3)
        XCTAssertEqual(s.marks, [.square, .square, .none])
    }

    func testMissingScoreMakesHoleUnresolved() {
        let r = round(players: [PlayerInput(id: "a"), PlayerInput(id: "b")],
                      scores: [[.strokes(4), nil, .strokes(3)], [.strokes(4), .strokes(5), .strokes(3)]])
        XCTAssertEqual(r.throughHole(seats: [0, 1]), 1, "stops at the first hole any participant is missing")
        XCTAssertEqual(r.throughHole(seats: [1]), 3)
        XCTAssertFalse(r.isComplete)
        XCTAssertFalse(r.isResolved(hole: 1, seats: [0, 1]))
        XCTAssertTrue(r.isResolved(hole: 2, seats: [0, 1]))
        let result = ScoringEngine.score(RoundInput(holes: 3, par: [4, 5, 3], strokeIndex: [], players: r.players,
                                                    scores: r.raw))
        XCTAssertEqual(result.status, .inProgress(throughHole: 1))
        XCTAssertEqual(result.perPlayer["a"]?.holesEntered, 2)
        XCTAssertEqual(result.perPlayer["a"]?.gross, 7)
    }

    func testToParNilWhenAnyPlayedHoleLacksPar() {
        let r = round(par: [4, nil, 3], players: [PlayerInput(id: "a")],
                      scores: [[.strokes(5), .strokes(6), .pickedUp]])
        let s = r.summary(seat: 0)
        XCTAssertNil(s.toPar)
        XCTAssertEqual(s.holeToPar, [1, nil, 3])
        XCTAssertEqual(s.effectiveStrokes, [5, 6, 6])
        XCTAssertEqual(s.marks, [.square, .none, .x])
        XCTAssertEqual(s.pickedUp, 1)
    }

    func testShortAndLongScoreRowsArePaddedAndTruncated() {
        let r = round(players: [PlayerInput(id: "a"), PlayerInput(id: "b")],
                      scores: [[.strokes(4)], [.strokes(4), .strokes(4), .strokes(4), .strokes(4)]])
        XCTAssertEqual(r.raw[0], [.strokes(4), nil, nil])
        XCTAssertEqual(r.raw[1].count, 3)
    }

    func testDisplayNameFallsBackToCapitalisedID() {
        let r = round(players: [PlayerInput(id: "tess"), PlayerInput(id: "mo", name: "Mo B.")], scores: [[], []])
        XCTAssertEqual(r.displayName("tess"), "Tess")
        XCTAssertEqual(r.displayName("mo"), "Mo B.")
    }
}
