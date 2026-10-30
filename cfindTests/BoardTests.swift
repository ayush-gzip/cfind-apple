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

    func testOrderIsLastMessageNotLastUpdate() {
        let msgs = """
        [{"id":"1","role":"user","text":"go","time":5},{"id":"2","role":"assistant","text":"done","time":8},
         {"id":"3","role":"tool","text":"ls","time":20},{"id":"4","role":"note","text":"mode","time":30}]
        """
        XCTAssertEqual(AgentsView.lastTalk(makeAgent(updatedAt: 40, messages: msgs)), 8)
        XCTAssertEqual(AgentsView.lastTalk(makeAgent(updatedAt: 40)), 40, "no messages yet: last update")
        let s = try! decode(Session.self, """
        {"id":"s","profile":"p","source":"claude","path":"/s","cwd":"/x","title":"t","updatedAt":9,"lastActive":3,"state":"idle"}
        """)
        XCTAssertEqual(s.lastActive, 3)
        XCTAssertNil(makeSession(state: "idle").lastActive, "an older daemon sends no lastActive")
    }
}
#endif
