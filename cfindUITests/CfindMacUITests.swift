import XCTest

#if os(macOS)
/// Runs against the dashboard daemon on this Mac (`cfind daemon start`).
final class CfindMacUITests: XCTestCase {
    func testDashboardLoadsAndShortcutsWork() throws {
        let app = XCUIApplication()
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 20), "no web view")
        XCTAssertTrue(web.buttons["Sessions"].waitForExistence(timeout: 20), "the dashboard did not load")

        app.typeKey("n", modifierFlags: .command)
        let form = web.staticTexts.matching(NSPredicate(format: "value == 'A new agent, ready to work.'")).firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 5), "⌘N did not open the new agent form")
        app.typeKey(.escape, modifierFlags: [])

        // ⌘B hides the sidebar and shows it again.
        app.typeKey("b", modifierFlags: .command)
        XCTAssertTrue(web.buttons["Sessions"].waitForNonExistence(timeout: 5), "⌘B did not hide the sidebar")
        app.typeKey("b", modifierFlags: .command)
        XCTAssertTrue(web.buttons["Sessions"].waitForExistence(timeout: 5), "⌘B did not show the sidebar")

        // ⌘K opens the command menu; Return runs the first command (New agent).
        // The menu's own fields are not checked: after an earlier dialog, WebKit's
        // accessibility tree did not list them, though the page had opened the menu.
        app.typeKey("k", modifierFlags: .command)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(form.waitForExistence(timeout: 5), "⌘K and Return did not open New agent")
        app.typeKey(.escape, modifierFlags: [])

        // ⌘+ and ⌘= zoom in, ⌘- out, ⌘0 back. The sidebar grows with the page.
        let button = web.buttons["Sessions"]
        let width = button.frame.width
        app.typeKey("=", modifierFlags: .command)
        app.typeKey("+", modifierFlags: .command)
        XCTAssertGreaterThan(button.frame.width, width * 1.1, "⌘+ did not zoom in")
        app.typeKey("-", modifierFlags: .command)
        app.typeKey("0", modifierFlags: .command)
        XCTAssertEqual(button.frame.width, width, accuracy: 1, "⌘0 did not reset the zoom")
    }
}
#endif
