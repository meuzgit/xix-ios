// Build Doc 3 step 1 acceptance, as real taps: two simulators, one round, New round to results, a guest
// joining by link mid-round. Run the owner test on one device and the guest test on another at the same
// time (scripts/acceptance-video.sh records both). They meet through files under /tmp/xix-video, which
// the simulator shares with the Mac. Against the local stack only.
import XCTest

final class PlayableLoopTests: XCTestCase {
    static let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["XIX_HANDOFF_DIR"] ?? "/tmp/xix-video")
    var codeFile: URL { Self.dir.appendingPathComponent("code.txt") }
    var guestDone: URL { Self.dir.appendingPathComponent("guest-done.txt") }

    override func setUp() { continueAfterFailure = false }

    // MARK: Owner: Ray sets the round up, scores hole 1 for both, then his own row while Dave plays his.

    func testOwnerPlaysRound() throws {
        try? FileManager.default.removeItem(at: codeFile)
        try? FileManager.default.removeItem(at: guestDone)
        let app = XCUIApplication()
        app.launch()
        pause(1.5)
        signOutIfSignedIn(app)

        app.buttons["New round"].tap()
        let course = app.textFields["courseField"]
        XCTAssertTrue(course.waitForExistence(timeout: 5))
        course.tap(); course.typeText("Fraserview")
        pause(0.6)
        app.buttons["9 holes"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Use “")).firstMatch.tap()

        // Par: hole 3 a par 3, hole 8 a par 5.
        XCTAssertTrue(app.buttons["par-3"].waitForExistence(timeout: 5))
        app.buttons["par-3"].tap(); pause(0.3); app.buttons["par-3"].tap(); pause(0.3)
        app.buttons["par-8"].tap(); pause(0.5)
        app.buttons["Next"].tap()

        // Players: Dave by name.
        let player = app.textFields["playerField"]
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        player.tap(); player.typeText("Dave")
        app.buttons["Add"].tap(); pause(0.6)
        app.buttons["Next"].tap()

        // Games: Skins and Nassau for both.
        XCTAssertTrue(app.buttons["game-skins-0"].waitForExistence(timeout: 5))
        for id in ["game-skins-0", "game-skins-1", "game-nassau-0", "game-nassau-1"] { app.buttons[id].tap(); pause(0.3) }
        pause(0.5)
        app.buttons["Next"].tap()

        signInLocallyIfAsked(app, name: "Ray")

        // Share: read the code, then play.
        let play = app.buttons["Play hole 1"]
        XCTAssertTrue(play.waitForExistence(timeout: 20))
        let link = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "xix.golf/r/")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 20))
        let code = String(link.label.dropFirst("xix.golf/r/".count))
        pause(2)
        play.tap()

        // Hole 1 for both rows, then hand the code to the guest.
        score(app, row: "Ray", strokes: 4)
        score(app, row: "Dave", strokes: 5)
        pause(1)
        try code.write(to: codeFile, atomically: true, encoding: .utf8)

        // Ray's own row on holes 2–9 while Dave scores his from the other phone.
        let rays = [3, 4, 3, 5, 4, 4, 5, 4]
        for (i, n) in rays.enumerated() {
            let hole = i + 2
            app.buttons["hole-\(hole)"].tap(); pause(0.8)
            score(app, row: "Ray", strokes: n)
            pause(1.2)
        }
        // A look at the grid while Dave finishes.
        app.buttons["layer-grid"].tap(); pause(2)
        waitForFile(guestDone, timeout: 240)
        pause(3)

        // End the round from the menu; every cell should be in.
        app.buttons["Round menu"].tap()
        let end = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "End round")).firstMatch
        XCTAssertTrue(end.waitForExistence(timeout: 5)); end.tap()
        let confirm = app.buttons["End round and see results"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); pause(2); confirm.tap()
        XCTAssertTrue(app.buttons["Share results"].waitForExistence(timeout: 60))
        let waiting = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "waiting for the final result")).firstMatch
        let deadline = Date().addingTimeInterval(90)
        while waiting.exists && Date() < deadline { pause(1) }
        XCTAssertFalse(waiting.exists, "the server's result arrived through the local webhook")
        pause(4)
        app.swipeUp(); pause(3)
    }

    // MARK: Guest: Dave joins from the link after hole 1, claims his row, scores his own holes.

    func testGuestJoinsMidRound() throws {
        waitForFile(codeFile, timeout: 300)
        let code = try String(contentsOf: codeFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let app = XCUIApplication()
        app.launch()
        pause(1)
        signOutIfSignedIn(app)
        app.terminate()
        app.launchArguments = ["-xix-open", "xix://r/\(code)"]
        app.launch()

        signInLocallyIfAsked(app, name: "Dave")
        let claim = app.buttons["Claim this row"]
        XCTAssertTrue(claim.waitForExistence(timeout: 20))
        pause(2)
        claim.tap()

        // Lands on the current hole (2). Dave scores his row hole by hole.
        XCTAssertTrue(app.buttons["score-Dave"].waitForExistence(timeout: 20))
        pause(1.5)
        let daves = [4, 3, 4, 4, 5, 3, 6, 4]
        for (i, n) in daves.enumerated() {
            let hole = i + 2
            app.buttons["hole-\(hole)"].tap(); pause(0.8)
            score(app, row: "Dave", strokes: n)
            pause(1.5)
        }
        pause(1)
        try "done".write(to: guestDone, atomically: true, encoding: .utf8)

        // The owner ends the round; the results arrive here on their own.
        XCTAssertTrue(app.buttons["Share results"].waitForExistence(timeout: 180))
        pause(4)
        app.swipeUp(); pause(3)
    }

    // MARK: Helpers

    private func score(_ app: XCUIApplication, row: String, strokes: Int) {
        let box = app.buttons["score-\(row)"]
        XCTAssertTrue(box.waitForExistence(timeout: 10))
        box.tap(); pause(0.5)
        app.buttons["pad-\(strokes)"].tap(); pause(0.4)
        app.buttons["pad-save"].tap(); pause(0.6)
    }

    /// A fresh start for the video: the debug menu's Sign out, when a session was restored.
    private func signOutIfSignedIn(_ app: XCUIApplication) {
        let debug = app.buttons["Debug menu"]
        guard debug.waitForExistence(timeout: 5) else { return }
        debug.tap()
        let out = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sign out")).firstMatch
        if out.waitForExistence(timeout: 3) { out.tap(); pause(1) } else { app.buttons["Back"].tap() }
        pause(1)
    }

    /// The simulator's own Apple Account prompt, if it appears over the sheet.
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Not Now", "Cancel", "OK"] {
            let b = springboard.buttons[label]
            if b.exists { b.tap(); pause(0.5) }
        }
    }

    private func signInLocallyIfAsked(_ app: XCUIApplication, name: String) {
        dismissSystemAlerts()
        let field = app.textFields["localName"]
        guard field.waitForExistence(timeout: 8) else { return }
        dismissSystemAlerts()
        pause(1)
        field.tap(); field.typeText(name)
        app.buttons["Sign in"].tap()
        pause(1)
    }

    private func waitForFile(_ url: URL, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while !FileManager.default.fileExists(atPath: url.path) && Date() < deadline { Thread.sleep(forTimeInterval: 1) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "waited \(Int(timeout))s for \(url.lastPathComponent)")
    }

    private func pause(_ s: TimeInterval) { Thread.sleep(forTimeInterval: s) }
}
