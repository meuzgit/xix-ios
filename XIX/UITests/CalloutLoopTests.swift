// Build Doc 3 step 3 acceptance: all four kinds of callout thrown from one phone, answered per target
// on two others, resolved by the engine, and read back on the results screen. Three simulators at once
// (scripts/acceptance-video.sh with XIX_SIM_C), against the local stack.
//
// Ray owns the round and keeps the card: he creates every callout and enters every score. Dave and Mo
// claim their rows and do the one thing the acceptance is about — answer, each for themselves.
import XCTest

final class CalloutLoopTests: XCTestCase {
    static let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["XIX_HANDOFF_DIR"] ?? "/tmp/xix-video")
    var codeFile: URL { Self.dir.appendingPathComponent("callout-code.txt") }
    func joined(_ who: String) -> URL { Self.dir.appendingPathComponent("callout-joined-\(who).txt") }
    func answered(_ n: Int) -> URL { Self.dir.appendingPathComponent("callout-answered-\(n).txt") }
    func thrown(_ n: Int) -> URL { Self.dir.appendingPathComponent("callout-thrown-\(n).txt") }

    override func setUp() { continueAfterFailure = false }

    // MARK: Ray: four callouts, four holes, then the results

    func testOwnerThrowsAllFourKinds() throws {
        for f in [codeFile, joined("dave"), joined("mo")] + (1...4).map { answered($0) } + (1...4).map { thrown($0) } {
            try? FileManager.default.removeItem(at: f)
        }
        let app = XCUIApplication()
        app.launch()
        pause(1.5)
        UITestFlow.signOutIfSignedIn(app)
        // Four on the card: Dave and Mo answer for themselves, Tess is scored by the owner and is the
        // partner in the third callout.
        UITestFlow.newRound(app, course: "Fraserview", guests: ["Dave", "Mo", "Tess"], games: ["skins"], name: "Ray")

        let play = app.buttons["Play hole 1"]
        XCTAssertTrue(play.waitForExistence(timeout: 25))
        let link = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "xix.golf/r/")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 20))
        let code = String(link.label.dropFirst("xix.golf/r/".count))
        try code.write(to: codeFile, atomically: true, encoding: .utf8)
        pause(1.5)
        play.tap()

        // Both have to be in the round before a callout can name them.
        UITestFlow.waitForFile(joined("dave"), timeout: 240)
        UITestFlow.waitForFile(joined("mo"), timeout: 240)
        pause(2)

        // 1 · Target on hole 1: both of them, par. Dave signs, Mo ducks.
        compose(app) { c in
            c.tap(kind: "target")
            c.tap(target: "Dave"); c.tap(target: "Mo")
            c.tap(goal: "par")
        }
        try "1".write(to: thrown(1), atomically: true, encoding: .utf8)
        UITestFlow.waitForFile(answered(1), timeout: 180)
        pause(1)
        score(app, hole: 1, [("Ray", 5), ("Dave", 4), ("Mo", 5), ("Tess", 4)])

        // 2 · Duel on hole 2: Ray against Dave.
        go(app, hole: 2)
        compose(app) { c in
            c.tap(kind: "duel")
            c.tap(target: "Dave")
        }
        try "2".write(to: thrown(2), atomically: true, encoding: .utf8)
        UITestFlow.waitForFile(answered(2), timeout: 180)
        pause(1)
        score(app, hole: 2, [("Ray", 4), ("Dave", 5), ("Mo", 5), ("Tess", 5)])

        // 3 · Partner on hole 3: Ray and Tess against the two of them.
        go(app, hole: 3)
        compose(app) { c in
            c.tap(kind: "partner")
            c.tap(target: "Dave"); c.tap(target: "Mo")
            c.tap(partner: "Tess")
        }
        try "3".write(to: thrown(3), atomically: true, encoding: .utf8)
        UITestFlow.waitForFile(answered(3), timeout: 180)
        pause(1)
        score(app, hole: 3, [("Ray", 5), ("Dave", 4), ("Mo", 4), ("Tess", 3)])

        // 4 · Double on hole 4: the Skins hole counts twice, if they both sign.
        go(app, hole: 4)
        compose(app) { c in
            c.tap(kind: "multiplier")
            c.tap(target: "Dave"); c.tap(target: "Mo")
        }
        try "4".write(to: thrown(4), atomically: true, encoding: .utf8)
        UITestFlow.waitForFile(answered(4), timeout: 180)
        pause(1)
        score(app, hole: 4, [("Ray", 3), ("Dave", 5), ("Mo", 5), ("Tess", 5)])

        // A hole closes to callouts the moment one of the people in it has a score. Hole 5, with Dave's
        // score already in: the composer says so and will not send. (The server refuses it too — that
        // path is pinned in XIXData's CalloutTests, where nothing can hide the round trip.)
        go(app, hole: 5)
        UITestFlow.score(app, row: "Dave", strokes: 4)
        pause(1)
        let open = app.buttons["composeCallout"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()
        XCTAssertTrue(app.buttons["composerSend"].waitForExistence(timeout: 10))
        pause(1)
        app.buttons["kind-duel"].tap(); pause(0.6)
        app.buttons["target-Dave"].tap(); pause(1)
        let problem = app.staticTexts["Dave has already scored this hole."]
        XCTAssertTrue(problem.waitForExistence(timeout: 5), "the composer refuses a hole that is already scored")
        XCTAssertFalse(app.buttons["composerSend"].isEnabled, "and Send is not offered")
        pause(3)
        app.buttons["composerClose"].tap()
        pause(1)

        // The rest of the card, so the round finishes properly.
        score(app, hole: 5, [("Ray", 4), ("Mo", 5), ("Tess", 4)])
        for hole in 6...9 {
            go(app, hole: hole)
            score(app, hole: hole, [("Ray", 4), ("Dave", 4), ("Mo", 5), ("Tess", 4)])
        }

        // End it and read the callouts back off the results screen.
        app.buttons["Round menu"].tap()
        let end = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "End round")).firstMatch
        XCTAssertTrue(end.waitForExistence(timeout: 8)); end.tap()
        let confirm = app.buttons["End round and see results"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8)); pause(1.5); confirm.tap()
        XCTAssertTrue(app.buttons["Share results"].waitForExistence(timeout: 90))
        pause(3)
        app.swipeUp(); pause(2)

        // All four, with what happened to each.
        for title in ["Beat par on 1", "Duel on 2", "Partner pick on 3", "Double on 4 · Skins"] {
            let row = app.staticTexts[title]
            XCTAssertTrue(row.waitForExistence(timeout: 20), "\(title) is on the results screen")
        }
        XCTAssertTrue(app.staticTexts["DAVE MADE IT · MO DUCKED"].exists, "the target says who made it and who ducked")
        XCTAssertTrue(app.staticTexts["DOUBLED"].exists, "the double simply counted twice")
        pause(4)
    }

    // MARK: Dave signs everything

    func testDaveAnswersAsATarget() throws {
        try answer(as: "Dave", responses: [1: "sign", 2: "sign", 3: "sign", 4: "sign"])
    }

    // MARK: Mo ducks the first and signs the rest

    func testMoDucksThenSigns() throws {
        try answer(as: "Mo", responses: [1: "duck", 3: "sign", 4: "sign"])
    }

    /// One target's whole job: join, claim, and answer each callout as it lands.
    private func answer(as who: String, responses: [Int: String]) throws {
        UITestFlow.waitForFile(codeFile, timeout: 300)
        let code = try String(contentsOf: codeFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let app = XCUIApplication()
        app.launch()
        pause(1)
        UITestFlow.signOutIfSignedIn(app)
        app.terminate()
        app.launchArguments = ["-xix-open", "xix://r/\(code)"]
        app.launch()
        UITestFlow.signInLocallyIfAsked(app, name: who)

        // With two rows still open the join screen asks which one is yours, so claim by name.
        let claim = app.buttons["claim-\(who)"]
        XCTAssertTrue(claim.waitForExistence(timeout: 30), "\(who)'s row is offered on the join screen")
        pause(1.5)
        claim.tap()
        XCTAssertTrue(app.buttons["hole-1"].waitForExistence(timeout: 25))
        try "in".write(to: joined(who.lowercased()), atomically: true, encoding: .utf8)

        for hole in 1...4 {
            guard let response = responses[hole] else { continue }
            UITestFlow.waitForFile(thrown(hole), timeout: 240)
            go(app, hole: hole)
            // The banner is the control: its two bubbles are SIGN IT and DUCK IT.
            let banner = app.descendants(matching: .any).matching(identifier: "callout-banner").firstMatch
            XCTAssertTrue(banner.waitForExistence(timeout: 60), "the callout for hole \(hole) reaches \(who)")
            pause(2)
            app.buttons[response == "sign" ? "callout-sign" : "callout-duck"].tap()
            pause(1.5)
            try response.write(to: answered(hole), atomically: true, encoding: .utf8)
        }

        // Watch the round end from here too.
        XCTAssertTrue(app.buttons["Share results"].waitForExistence(timeout: 300))
        pause(4)
    }

    // MARK: Taps

    private func go(_ app: XCUIApplication, hole: Int) {
        let button = app.buttons["hole-\(hole)"]
        if button.waitForExistence(timeout: 10) { button.tap(); pause(0.8) }
    }

    private func score(_ app: XCUIApplication, hole: Int, _ rows: [(String, Int)]) {
        for (name, strokes) in rows { UITestFlow.score(app, row: name, strokes: strokes) }
    }

    /// Open the composer, make the choices, send.
    private func compose(_ app: XCUIApplication, expectRefusal: Bool = false, _ choices: (Composer) -> Void) {
        let open = app.buttons["composeCallout"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()
        let composer = Composer(app: app)
        XCTAssertTrue(app.buttons["composerSend"].waitForExistence(timeout: 10), "the composer opens")
        pause(1)
        choices(composer)
        pause(1.5)
        app.buttons["composerSend"].tap()
        pause(expectRefusal ? 1 : 2)
    }

    struct Composer {
        let app: XCUIApplication
        func tap(kind: String) { app.buttons["kind-\(kind)"].tap(); pause(0.6) }
        func tap(target: String) { app.buttons["target-\(target)"].tap(); pause(0.5) }
        func tap(goal: String) { app.buttons["goal-\(goal)"].tap(); pause(0.5) }
        func tap(partner: String) { app.buttons["partner-\(partner)"].tap(); pause(0.5) }
        func tap(game: String) { app.buttons["game-\(game)"].tap(); pause(0.5) }
        private func pause(_ s: TimeInterval) { Thread.sleep(forTimeInterval: s) }
    }

    private func pause(_ s: TimeInterval) { Thread.sleep(forTimeInterval: s) }
}
