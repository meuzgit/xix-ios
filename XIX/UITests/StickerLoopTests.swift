// Build Doc 3 step 2 acceptance, second half: a sticker thrown on one phone, opened on the other, and
// the sender told. Run the two tests on two booted simulators at the same time
// (`XIX_TESTS_A`/`XIX_TESTS_B` in scripts/acceptance-video.sh). Against the local stack only.
import XCTest

final class StickerLoopTests: XCTestCase {
    static let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["XIX_HANDOFF_DIR"] ?? "/tmp/xix-video")
    var codeFile: URL { Self.dir.appendingPathComponent("sticker-code.txt") }
    var openedFile: URL { Self.dir.appendingPathComponent("sticker-opened.txt") }

    override func setUp() { continueAfterFailure = false }

    // MARK: Ray throws a YIKES at Dave's blow-up, and is told when Dave opens it.

    func testSenderIsToldWhenTheStickerIsOpened() throws {
        try? FileManager.default.removeItem(at: codeFile)
        try? FileManager.default.removeItem(at: openedFile)
        let app = XCUIApplication()
        app.launch()
        pause(1.5)
        UITestFlow.signOutIfSignedIn(app)

        UITestFlow.newRound(app, course: "Fraserview", guest: "Dave", name: "Ray")

        let play = app.buttons["Play hole 1"]
        XCTAssertTrue(play.waitForExistence(timeout: 25))
        let link = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "xix.golf/r/")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 20))
        let code = String(link.label.dropFirst("xix.golf/r/".count))
        pause(1.5)
        play.tap()

        // A par for Ray and a blow-up for Dave: the tray opens on YIKES first.
        UITestFlow.score(app, row: "Ray", strokes: 4)
        UITestFlow.score(app, row: "Dave", strokes: 7)
        pause(1)
        try code.write(to: codeFile, atomically: true, encoding: .utf8)

        // Throw it: Dave's chip opens the tray, one tap sends.
        let chip = app.buttons["tray-for-Dave"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        pause(1)
        chip.tap()
        let yikes = app.buttons["tray-YIKES"]
        XCTAssertTrue(yikes.waitForExistence(timeout: 10), "the tray offers YIKES on a blow-up")
        pause(1.5)
        yikes.tap()
        pause(2)

        // Dave opens it on his phone; this one is told, in ink, on the card.
        let told = app.staticTexts["Dave opened your YIKES"]
        XCTAssertTrue(told.waitForExistence(timeout: 180), "the sender is told the sticker was opened")
        pause(4)
    }

    // MARK: Dave joins, finds the sticker on his row, taps it and watches it play.

    func testGuestOpensTheSticker() throws {
        UITestFlow.waitForFile(codeFile, timeout: 300)
        let code = try String(contentsOf: codeFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let app = XCUIApplication()
        app.launch()
        pause(1)
        UITestFlow.signOutIfSignedIn(app)
        app.terminate()
        app.launchArguments = ["-xix-open", "xix://r/\(code)"]
        app.launch()

        UITestFlow.signInLocallyIfAsked(app, name: "Dave")
        let claim = app.buttons["Claim this row"]
        XCTAssertTrue(claim.waitForExistence(timeout: 25))
        pause(1.5)
        claim.tap()

        // He lands on the current hole; the sticker was thrown on hole 1, so go there.
        let holeOne = app.buttons["hole-1"]
        XCTAssertTrue(holeOne.waitForExistence(timeout: 25))
        pause(1.5)
        holeOne.tap()
        pause(1)

        // The sticker lands on his row while he watches.
        let anySticker = app.descendants(matching: .any).matching(identifier: "sticker-YIKES").firstMatch
        XCTAssertTrue(anySticker.waitForExistence(timeout: 120), "the YIKES arrives on Dave's row")
        pause(2)
        anySticker.tap()

        // It plays full screen: the poster names who threw it and says they will be told.
        let caption = app.descendants(matching: .any).matching(identifier: "playedStickerCaption").firstMatch
        if !caption.waitForExistence(timeout: 12) {
            let poster = app.descendants(matching: .any).matching(identifier: "playedSticker").firstMatch
            XCTAssertTrue(poster.exists, "the slap plays full screen — screen was:\n\(app.debugDescription)")
            pause(3)
            poster.tap()
        } else {
            XCTAssertEqual(caption.label, "Ray is told you opened it", "the poster names the sender")
            pause(3)
            caption.tap()
        }
        pause(2)
        try "done".write(to: openedFile, atomically: true, encoding: .utf8)
        pause(4)
    }

    private func pause(_ s: TimeInterval) { Thread.sleep(forTimeInterval: s) }
}

/// The setup taps both acceptance suites share.
enum UITestFlow {
    static func pause(_ s: TimeInterval) { Thread.sleep(forTimeInterval: s) }

    /// A fresh start for the video: the debug Sign out, when a session was restored.
    static func signOutIfSignedIn(_ app: XCUIApplication) {
        let settings = app.buttons["Settings"]
        guard settings.waitForExistence(timeout: 5) else { return }
        settings.tap()
        let out = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sign out")).firstMatch
        if out.waitForExistence(timeout: 3) { out.tap(); pause(1) }
        let back = app.buttons["Back"]
        if back.exists { back.tap() }
        pause(1)
    }

    static func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Not Now", "Cancel", "OK"] {
            let b = springboard.buttons[label]
            if b.exists { b.tap(); pause(0.5) }
        }
    }

    static func signInLocallyIfAsked(_ app: XCUIApplication, name: String) {
        dismissSystemAlerts()
        let field = app.textFields["localName"]
        guard field.waitForExistence(timeout: 8) else { return }
        dismissSystemAlerts()
        pause(1)
        field.tap(); field.typeText(name)
        app.buttons["Sign in"].tap()
        pause(1)
    }

    /// Course, par, guests, games, sign-in, as far as the share screen.
    static func newRound(_ app: XCUIApplication, course: String, guests: [String], games: [String] = [], name: String) {
        app.buttons["New round"].tap()
        let field = app.textFields["courseField"]
        _ = field.waitForExistence(timeout: 5)
        field.tap(); field.typeText(course)
        pause(0.6)
        app.buttons["9 holes"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Use “")).firstMatch.tap()
        _ = app.buttons["par-3"].waitForExistence(timeout: 5)
        pause(0.5)
        app.buttons["Next"].tap()
        let player = app.textFields["playerField"]
        _ = player.waitForExistence(timeout: 5)
        for guest in guests {
            player.tap(); player.typeText(guest)
            app.buttons["Add"].tap(); pause(0.6)
        }
        app.buttons["Next"].tap()
        _ = app.buttons["game-skins-0"].waitForExistence(timeout: 5)
        pause(0.4)
        // Every seat into every named game.
        for game in games {
            for seat in 0..<(guests.count + 1) {
                let toggle = app.buttons["game-\(game)-\(seat)"]
                if toggle.exists { toggle.tap(); pause(0.3) }
            }
        }
        pause(0.4)
        app.buttons["Next"].tap()
        signInLocallyIfAsked(app, name: name)
    }

    /// The single-guest form the earlier suites use.
    static func newRound(_ app: XCUIApplication, course: String, guest: String, name: String) {
        newRound(app, course: course, guests: [guest], games: [], name: name)
    }

    static func score(_ app: XCUIApplication, row: String, strokes: Int) {
        let box = app.buttons["score-\(row)"]
        _ = box.waitForExistence(timeout: 10)
        box.tap(); pause(0.5)
        app.buttons["pad-\(strokes)"].tap(); pause(0.4)
        app.buttons["pad-save"].tap(); pause(0.6)
    }

    static func waitForFile(_ url: URL, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while !FileManager.default.fileExists(atPath: url.path) && Date() < deadline { Thread.sleep(forTimeInterval: 1) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "waited \(Int(timeout))s for \(url.lastPathComponent)")
    }
}
