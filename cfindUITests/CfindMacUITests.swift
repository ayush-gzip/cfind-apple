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
    }
}
#endif
