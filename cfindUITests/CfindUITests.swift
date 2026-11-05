import XCTest

#if os(iOS)

/// Runs against a real dashboard on the Mac. xcodebuild passes
/// TEST_RUNNER_CFIND_BASE, TEST_RUNNER_CFIND_CODE and TEST_RUNNER_CFIND_CWD.
final class CfindUITests: XCTestCase {
    let env = ProcessInfo.processInfo.environment

    /// Launches unpaired and pairs with the code from the environment.
    func pairedApp() throws -> XCUIApplication {
        let base = try XCTUnwrap(env["CFIND_BASE"]), code = try XCTUnwrap(env["CFIND_CODE"])
        let app = XCUIApplication()
        app.launchArguments = ["-cfind-reset"]
        app.launch()

        let address = app.textFields["pair-address"]
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        shot(app, "1-pair")
        address.tap()
        address.typeText(base)
        app.textFields["pair-code"].tap()
        app.textFields["pair-code"].typeText(code)
        app.buttons["pair-button"].tap()

        XCTAssertTrue(app.navigationBars["Sessions"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.cells.element(boundBy: 1).waitForExistence(timeout: 20), "no sessions arrived")
        shot(app, "2-sessions")
        return app
    }

    /// Needs CFIND_QUERY: a word that is in some message text but in no title.
    func testBoardUsageAndFullTextSearch() throws {
        let query = try XCTUnwrap(env["CFIND_QUERY"])
        let app = try pairedApp()

        app.tabBars.buttons["Agents"].tap()
        XCTAssertTrue(app.staticTexts["Running"].waitForExistence(timeout: 5), "no Running lane")
        XCTAssertFalse(app.staticTexts["No agents yet. Start one, or continue a session from Sessions."].exists)
        shot(app, "b1-agents")

        app.tabBars.buttons["Usage"].tap()
        shot(app, "b2-usage")

        app.tabBars.buttons["Sessions"].tap()
        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 5) {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "tree"
            tree.lifetime = .keepAlways
            add(tree)
        }
        field.tap()
        field.typeText(query + "\n")
        XCTAssertTrue(app.staticTexts["Message text"].waitForExistence(timeout: 30), "no full text section")
        XCTAssertFalse(app.staticTexts["No matches"].exists)
        shot(app, "b3-search")
    }

    func testPairStartAgentApproveAndReply() throws {
        let cwd = try XCTUnwrap(env["CFIND_CWD"])
        let app = try pairedApp()

        app.tabBars.buttons["Agents"].tap()
        app.buttons["new-agent"].tap()
        let folder = app.textFields["new-folder"]
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        // A long path is cut off on screen, so a tap can land mid-text. Delete
        // before the cursor, then tap the end of what is left, until it is empty.
        for _ in 0..<4 {
            let old = folder.value as? String ?? ""
            if old.isEmpty || old == folder.placeholderValue { break }
            folder.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
            folder.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        }
        folder.typeText(cwd)
        XCTAssertEqual(folder.value as? String, cwd)
        // Multi-line fields show up as text views.
        let prompt = app.descendants(matching: .any)["new-prompt"]
        prompt.tap()
        prompt.typeText(
            "Create a file named phone.txt that contains hi. Then reply with only the result of 6 times 7.")
        shot(app, "3-new-agent")
        app.buttons["start-agent"].tap()

        // The Write needs approval unless the profile already allows it.
        let allow = app.buttons["Allow once"]
        let answer = exact(app, "42")
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline && !answer.exists {
            if allow.exists {
                shot(app, "4-approval")
                allow.tap()
            }
            _ = answer.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(answer.exists, "no reply 42")
        shot(app, "5-reply")

        let composer = app.descendants(matching: .any)["composer"]
        composer.tap()
        composer.typeText("What is 10 plus 5? Reply with only the number.")
        app.buttons["send"].tap()
        XCTAssertTrue(exact(app, "15").waitForExistence(timeout: 120), "no reply 15")
        shot(app, "6-follow-up")
    }

    /// Opens a session and types in the message box. Nothing is sent.
    func testSessionMessageBox() throws {
        let app = try pairedApp()
        app.cells.element(boundBy: 1).tap()
        let composer = app.descendants(matching: .any)["composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10), "no message box")
        shot(app, "c1-empty")
        composer.tap()
        composer.typeText("Draft only, not sent")
        XCTAssertTrue(app.buttons["send"].isEnabled, "send is off with text in the box")
        shot(app, "c2-typed")
    }

    /// Needs tools/phone-harness.mjs and CFIND_AGENT (its agent id): a phone
    /// notification's link opens that chat in the Agents tab.
    func testOpenLinkShowsChat() throws {
        let app = try pairedApp()
        let id = try XCTUnwrap(env["CFIND_AGENT"])
        // open(_:) launches the app again with its arguments; -cfind-reset would unpair it.
        app.launchArguments = []
        app.open(URL(string: "cfind://open?agent=\(id)")!)
        XCTAssertTrue(app.descendants(matching: .any)["composer"].waitForExistence(timeout: 10), "the chat did not open")
        XCTAssertTrue(app.tabBars.buttons["Agents"].isSelected)
        XCTAssertTrue(exact(app, "slow task").exists)
        shot(app, "o1-open-link")
    }

    /// Needs tools/phone-harness.mjs (a scratch daemon): a dashboard agent working
    /// on "slow task", and a tmux session "Terminal test" waiting on a menu.
    func testSendNowStopAndTerminalView() throws {
        let app = try pairedApp()
        let composer = app.descendants(matching: .any)["composer"]

        // A queued message to a working agent goes at once.
        app.tabBars.buttons["Agents"].tap()
        containing(app, "slow task").tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 10), "no message box")
        XCTAssertFalse(app.buttons["send-now"].exists)
        composer.tap()
        composer.typeText("then this")
        app.buttons["send"].tap()
        XCTAssertTrue(app.buttons["send-now"].waitForExistence(timeout: 10), "no Send now on the queued message")
        shot(app, "s1-queued")
        app.buttons["send-now"].tap()
        XCTAssertTrue(exact(app, "reply to then this").waitForExistence(timeout: 10), "the queued message did not run")
        XCTAssertFalse(app.buttons["send-now"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // A terminal menu is answered with the key buttons.
        app.tabBars.buttons["Sessions"].tap()
        containing(app, "Terminal test").tap()
        let screen = app.staticTexts["terminal-screen"]
        XCTAssertTrue(screen.waitForExistence(timeout: 10), "no terminal view while it waits")
        XCTAssertTrue(until { screen.label.contains("Pick a colour") }, screen.label)
        app.buttons["key-Down"].tap()
        XCTAssertTrue(until { screen.label.contains("❯ 2. Blue") }, screen.label)
        shot(app, "t1-menu")
        app.buttons["key-Enter"].tap()
        XCTAssertTrue(until(15) { !screen.exists }, "the terminal view stayed after the answer")

        // While it works: Stop, and Send now after a message.
        XCTAssertTrue(app.buttons["stop"].waitForExistence(timeout: 10), "no Stop while it works")
        composer.tap()
        composer.typeText("stop the ping")
        app.buttons["send"].tap()
        XCTAssertTrue(app.buttons["send-now"].waitForExistence(timeout: 10), "no Send now after a message")
        shot(app, "t2-send-now")
        app.buttons["send-now"].tap()
        XCTAssertTrue(until { !app.buttons["send-now"].exists }, "Send now stayed")
        app.buttons["terminal-toggle"].tap()
        XCTAssertTrue(until { screen.exists && screen.label.contains("Got: stop the ping") && screen.label.contains("Sent now") },
                      screen.exists ? screen.label : "no terminal view")
        shot(app, "t3-running")
        app.buttons["stop"].tap()
        XCTAssertTrue(until(15) { !app.buttons["stop"].exists }, "still running after Stop")
        app.buttons["terminal-toggle"].tap()
        XCTAssertTrue(until { screen.exists && screen.label.contains("Stopped") }, screen.exists ? screen.label : "no terminal view")
        shot(app, "t4-stopped")
    }

    func until(_ seconds: TimeInterval = 10, _ check: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if check() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return check()
    }

    /// Needs a demo daemon with made-up sessions: screenshots of each screen, nothing sent.
    func testScreens() throws {
        let app = try pairedApp()
        // A row shows its question in place of its title once it asks one.
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@",
                                             "The checkout test", "open a pull request")).firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["composer"].waitForExistence(timeout: 10))
        sleep(2)
        shot(app, "s1-chat-end")
        app.swipeDown()
        app.swipeDown()
        shot(app, "s2-chat-top")
        app.navigationBars.buttons.firstMatch.tap()

        app.tabBars.buttons["Agents"].tap()
        sleep(1)
        shot(app, "s3-agents")
        containing(app, "Design a new app icon").tap()
        XCTAssertTrue(app.descendants(matching: .any)["composer"].waitForExistence(timeout: 10))
        sleep(2)
        shot(app, "s4-question")
        app.navigationBars.buttons.firstMatch.tap()

        app.tabBars.buttons["Usage"].tap()
        sleep(1)
        shot(app, "s5-usage")

        // The largest text size, still paired.
        app.terminate()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Sessions"].waitForExistence(timeout: 10))
        sleep(2)
        shot(app, "x1-sessions")
        containing(app, "open a pull request").tap()
        XCTAssertTrue(app.descendants(matching: .any)["composer"].waitForExistence(timeout: 10))
        sleep(2)
        shot(app, "x2-chat")
    }

    /// Drives the app slowly for the demo video (context-find/demo/video). Each step
    /// prints a CFIND_DEMO line with the time and where it tapped, for the edit.
    /// Needs a demo daemon with made-up sessions; skipped unless CFIND_DEMO is set.
    func testDemo() throws {
        try XCTSkipIf(env["CFIND_DEMO"] == nil, "Only for the demo video")
        let app = try pairedApp()
        let size = app.frame.size
        func log(_ fields: [String: Any]) {
            var fields = fields
            if fields["t"] == nil && fields["t0"] == nil { fields["t"] = Date().timeIntervalSince1970 }
            let json = try! JSONSerialization.data(withJSONObject: fields)
            print("CFIND_DEMO " + String(decoding: json, as: UTF8.self))
        }
        func scene(_ id: String) { log(["type": "scene", "id": id]) }
        // XCUITest waits for the app to settle before it touches, so the touch lands
        // a moment after the call.
        func tap(_ element: XCUIElement) {
            let f = element.frame
            log(["type": "tap", "t": Date().timeIntervalSince1970 + 0.15, "x": f.midX / size.width, "y": f.midY / size.height])
            element.tap()
        }

        // The recorder flashes dark mode on this line to sync the video's clock.
        log(["type": "sync"])
        sleep(3)
        scene("sessions")
        sleep(4)
        scene("chat")
        tap(containing(app, "open a pull request"))
        sleep(3)
        app.swipeDown(velocity: .slow)
        sleep(2)
        tap(app.navigationBars.buttons.firstMatch)
        sleep(1)
        scene("follow-up")
        tap(app.tabBars.buttons["Agents"])
        sleep(2)
        tap(containing(app, "release notes"))
        sleep(3)
        let composer = app.descendants(matching: .any)["composer"]
        tap(composer)
        sleep(1)
        let f = composer.frame
        let typed = Date().timeIntervalSince1970
        composer.typeText("Make it shorter, three bullets")
        log(["type": "type", "t0": typed, "t1": Date().timeIntervalSince1970, "x": f.midX / size.width, "y": f.midY / size.height])
        sleep(1)
        tap(app.buttons["send"])
        sleep(5)
        tap(app.navigationBars.buttons.firstMatch)
        sleep(1)
        scene("usage")
        tap(app.tabBars.buttons["Usage"])
        sleep(4)
        scene("end")
    }

    /// A list row's preview can start with its state, as in "Running · slow task".
    func containing(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// A bubble whose whole text is the answer, so the prompt and times never match.
    func exact(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@", text, text + ".")).firstMatch
    }

    func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
#endif
