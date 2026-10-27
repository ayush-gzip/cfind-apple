#if os(iOS)
import XCTest
@testable import cfind

@MainActor
final class ModelTests: XCTestCase {
    func model() throws -> AppModel {
        let m = AppModel()
        m.snapshot = try fixture(Snapshot.self, "snapshot")
        return m
    }

    func testProfileLookups() throws {
        let m = try model()
        XCTAssertEqual(m.label("personal"), "Claude · Personal")
        XCTAssertEqual(m.shortLabel("personal"), "Personal")
        XCTAssertEqual(m.shortLabel("claude"), "Claude")
        XCTAssertEqual(m.label("gone"), "gone")
        XCTAssertEqual(m.agentName("codex"), "Codex")
        XCTAssertEqual(m.agentName("personal"), "Claude")
    }

    func testSubagentsOfBusyParent() throws {
        let m = try model()
        let found = m.subagents(of: "s1", profile: "claude", parentState: "running")
        XCTAssertEqual(found.shown.map(\.path), ["/sub/1"])
        XCTAssertEqual(found.more, 0)
        XCTAssertTrue(m.subagents(of: nil, profile: "claude", parentState: "running").shown.isEmpty)
        XCTAssertTrue(m.subagents(of: "s1", profile: "personal", parentState: "running").shown.isEmpty)
    }

    func testSubagentsOfIdleParentOnlyLiveOnes() {
        let m = AppModel()
        m.snapshot = Snapshot(profiles: [], sessions: [
            makeSession("/a", id: "a", profile: "c", state: "idle", updatedAt: 1, parent: "s"),
            makeSession("/b", id: "b", profile: "c", state: "running", updatedAt: 2, parent: "s"),
            makeSession("/c", id: "c", profile: "c", state: "waiting", updatedAt: 3, parent: "s"),
        ])
        let idle = m.subagents(of: "s", profile: "c", parentState: "idle")
        XCTAssertEqual(idle.shown.map(\.path), ["/c", "/b"])
        let busy = m.subagents(of: "s", profile: "c", parentState: "running")
        XCTAssertEqual(busy.shown.map(\.path), ["/c", "/b", "/a"])
    }

    func testSubagentsShowFiveAndCountTheRest() {
        let m = AppModel()
        m.snapshot = Snapshot(profiles: [], sessions: (1...8).map {
            makeSession("/\($0)", profile: "c", state: "running", updatedAt: Double($0), parent: "s")
        })
        let found = m.subagents(of: "s", profile: "c", parentState: "running")
        XCTAssertEqual(found.shown.map(\.path), ["/8", "/7", "/6", "/5", "/4"])
        XCTAssertEqual(found.more, 3)
    }

    func testAgentForSessionMatchesHistoryOrSid() throws {
        let m = try model()
        let ws = try fixture(Workspace.self, "workspace")
        m.agents = ws.agents
        let byHistory = makeSession("/home/u/.claude/projects/p/a1.jsonl", id: "other", profile: "claude", state: "idle")
        XCTAssertEqual(m.agent(for: byHistory)?.id, "a1")
        let bySid = makeSession("/x", id: "sid-1", profile: "claude", state: "idle")
        XCTAssertEqual(m.agent(for: bySid)?.id, "a1")
        let otherProfile = makeSession("/x", id: "sid-1", profile: "codex", state: "idle")
        XCTAssertNil(m.agent(for: otherProfile))
    }
}
#endif
