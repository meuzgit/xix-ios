import XCTest
@testable import XIXScoring

/// B.8 edge cases, one fixture each (B.9 names where given).
final class EdgeCaseTests: XCTestCase {
    func testB8_5_PickedUpOnParFive() throws {
        try FixtureRunner.run("pickup_par5")
    }
}
