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
