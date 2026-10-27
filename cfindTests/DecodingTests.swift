import XCTest
@testable import cfind

/// The JSON files are the shapes the daemon sends; ts/test/iphone_contract.test.ts
/// in context-find checks the server keeps them.
final class DecodingTests: XCTestCase {
    func testSnapshot() throws {
        let snap = try fixture(Snapshot.self, "snapshot")
        XCTAssertEqual(snap.profiles.map(\.id), ["claude", "personal", "codex"])
        XCTAssertEqual(snap.profiles[0].limits?.plan, "max")
        XCTAssertEqual(snap.profiles[0].limits?.session?.used, 42.5)
        XCTAssertNil(snap.profiles[2].limits)
        XCTAssertEqual(snap.sessions.count, 3)

        let main = snap.sessions[0]
        XCTAssertEqual(main.path, "/home/u/.claude/projects/p/s1.jsonl")
        XCTAssertEqual(main.tmux, true)
        XCTAssertEqual(main.open, true)
        XCTAssertNil(main.parent)

        let sub = snap.sessions[1]
        XCTAssertEqual(sub.parent, "s1")
        XCTAssertNil(sub.open)
        XCTAssertNil(sub.tmux)
    }

    func testWorkspace() throws {
        let ws = try fixture(Workspace.self, "workspace")
        XCTAssertEqual(ws.agents.count, 1)
        let a = ws.agents[0]
        XCTAssertEqual(a.state, "waiting")
        XCTAssertEqual(a.model, "sonnet")
        XCTAssertEqual(a.pending?.method, "can_use_tool")
        XCTAssertEqual(a.pending?.id.key, "7.0")
        XCTAssertEqual(a.pending?.params?["tool_name"]?.string, "Write")
        XCTAssertEqual(a.queue.map(\.text), ["then run the tests"])
        XCTAssertEqual(a.messages.count, 3)
        XCTAssertNil(a.messages[0].tool)
        XCTAssertEqual(a.messages[1].tool?.name, "Write")
        XCTAssertEqual(a.messages[1].tool?.error, false)
        XCTAssertEqual(a.messages[2].images, ["up1"])
    }

    func testPendingIdMayBeStringOrNumber() throws {
        XCTAssertEqual(try decode(Pending.self, #"{"id":"abc","method":"m"}"#).id.key, "abc")
        XCTAssertEqual(try decode(Pending.self, #"{"id":7,"method":"m"}"#).id.key, "7.0")
    }

    func testMissingRequiredFieldFails() {
        XCTAssertThrowsError(try decode(Session.self, #"{"id":"s"}"#))
        XCTAssertThrowsError(try decode(Agent.self, #"{"id":"a","profile":"p"}"#))
    }

    func testConversation() throws {
        let c = try decode(Conversation.self, #"{"messages":[{"id":"1","role":"user","text":"hi","time":5}],"omitted":2}"#)
        XCTAssertEqual(c.omitted, 2)
        XCTAssertEqual(c.messages[0].time, 5)
    }
}
