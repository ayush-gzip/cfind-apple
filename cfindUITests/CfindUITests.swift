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

    /// Needs tools/phone-harness.mjs (a scratch daemon): a dashboard agent working
    /// on "slow task", and a tmux session "Terminal test" waiting on a menu.
    func testSendNowStopAndTerminalView() throws {
        let app = try pairedApp()
        let composer = app.descendants(matching: .any)["composer"]

        // A queued message to a working agent goes at once.
        app.tabBars.buttons["Agents"].tap()
        app.staticTexts["slow task"].firstMatch.tap()
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
        app.staticTexts["Terminal test"].firstMatch.tap()
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
