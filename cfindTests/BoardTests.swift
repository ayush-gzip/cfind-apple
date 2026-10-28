#if os(iOS)
import XCTest
@testable import cfind

final class BoardTests: XCTestCase {
    func testAgentLaneOrder() {
        XCTAssertEqual(AgentsView.lanes.count, 4)
        XCTAssertEqual(AgentsView.lane("waiting"), 0)
        XCTAssertEqual(AgentsView.lane("asking"), 0)
        XCTAssertEqual(AgentsView.lane("running"), 1)
        XCTAssertEqual(AgentsView.lane("stale"), 1)
        XCTAssertEqual(AgentsView.lane("queued"), 2)
        XCTAssertEqual(AgentsView.lane("idle"), 3)
        XCTAssertEqual(AgentsView.lane("failed"), 3)
    }
}
#endif
