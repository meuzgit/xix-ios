import Foundation
import XCTest
@testable import XIXScoring

final class FixtureTests: XCTestCase {
    func testFraserviewInputDecodesAndRoundTrips() throws {
        let fixture = try FixtureLoader.load("fraserview_2026-09-09")
        let input = fixture.input

        XCTAssertEqual(input.holes, 18)
        XCTAssertEqual(input.players.map(\.id), ["ray", "dave", "mo", "tess"])
        XCTAssertEqual(input.scores.count, 4)
        XCTAssertEqual(input.scores[2][12], .pickedUp, "Mo picks up on 13")
        XCTAssertEqual(input.games.map(\.format), [.nassau, .skins, .stableford])
        XCTAssertEqual(input.games[1].options.carryover, true)
        XCTAssertEqual(input.games[1].options.validation, false)
        XCTAssertEqual(input.callouts[0].params.goal, .par)
        XCTAssertEqual(input.callouts[0].responses, ["dave": .signed])
        XCTAssertEqual(input.callouts[1].responses, ["dave": .ducked])

        let encoded = try JSONEncoder().encode(input)
        let again = try JSONDecoder().decode(RoundInput.self, from: encoded)
        XCTAssertEqual(again, input)
    }

    func testResultCodableRoundTrip() throws {
        let fixture = try FixtureLoader.load("fraserview_2026-09-09")
        let result = ScoringEngine.score(fixture.input)
        let encoded = try JSONEncoder().encode(result)
        let again = try JSONDecoder().decode(RoundResult.self, from: encoded)
        XCTAssertEqual(again, result)
        XCTAssertEqual(try JSONValue(encoding: again), try JSONValue(encoding: result))
    }

    func testFraserviewFixture() throws {
        let result = try FixtureRunner.run("fraserview_2026-09-09")
        XCTAssertEqual(result.engineVersion, 1)
        XCTAssertEqual(result.status, .complete)
    }
}
