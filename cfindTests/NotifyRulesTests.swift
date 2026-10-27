import XCTest
@testable import cfind

final class NotifyRulesTests: XCTestCase {
    let pend = #"{"id":5,"method":"can_use_tool","params":{"tool_name":"Bash","display_name":"Run shell"}}"#
    let msgs = """
    [{"id":"1","role":"user","text":"hi"},{"id":"2","role":"assistant","text":"Done\\nwith   it."},
     {"id":"3","role":"assistant","text":"tool","tool":{"name":"Bash","input":"ls"}}]
    """

    func state(_ a: [Agent] = [], _ s: [Session] = []) -> NotifyState { NotifyState(agents: a, sessions: s) }

    func run(_ old: NotifyState?, _ new: NotifyState, viewing: NotifyTarget? = nil) -> [Note] {
        notes(old: old, new: new, viewing: viewing, agentName: { $0 == "p" ? "Claude" : "Codex" })
    }

    func testFirstUpdateIsSilent() {
        XCTAssertTrue(run(nil, state([makeAgent(pending: pend)], [makeSession(state: "waiting")])).isEmpty)
    }

    func testPendingApprovalNotifiesOnce() {
        let n = run(state([makeAgent()]), state([makeAgent(pending: pend)]))
        XCTAssertEqual(n.count, 1)
        XCTAssertEqual(n.first?.title, "Claude needs your input")
        XCTAssertEqual(n.first?.body, "Fix bug: Run shell")
        XCTAssertEqual(n.first?.id, "agent:a1:pending:5.0")
        XCTAssertEqual(n.first?.target, .agent("a1"))
        XCTAssertTrue(run(state([makeAgent(pending: pend)]), state([makeAgent(pending: pend)])).isEmpty)
    }

    func testPendingBodyPerRequestKind() {
        func body(_ pending: String) -> String? {
            run(state([makeAgent()]), state([makeAgent(pending: pending)])).first?.body
        }
        let ask = #"{"id":"q","method":"can_use_tool","params":{"tool_name":"AskUserQuestion","input":{"questions":[{"question":"Tea or coffee?"}]}}}"#
        XCTAssertEqual(body(ask), "Fix bug: Tea or coffee?")
        XCTAssertEqual(body(#"{"id":9,"method":"item/commandExecution/requestApproval","params":{"command":"curl x"}}"#),
                       "Fix bug: curl x")
        XCTAssertEqual(body(#"{"id":9,"method":"item/fileChange/requestApproval","params":{}}"#), "Fix bug: file changes")
        XCTAssertEqual(body(#"{"id":9,"method":"item/permissions/requestApproval","params":{}}"#), "Fix bug: a request")
    }

    func testAgentReplied() {
        let n = run(state([makeAgent(state: "running")]), state([makeAgent(state: "idle", updatedAt: 7, messages: msgs)]))
        XCTAssertEqual(n.count, 1)
        XCTAssertEqual(n.first?.title, "Claude replied")
        XCTAssertEqual(n.first?.body, "Done with it.")
        XCTAssertEqual(n.first?.id, "agent:a1:done:7.0")
        XCTAssertTrue(run(state([makeAgent(state: "running", pending: pend)]), state([makeAgent(state: "idle", pending: pend)])).isEmpty)
        XCTAssertTrue(run(state([makeAgent()]), state([makeAgent(updatedAt: 9)])).isEmpty)
    }

    func testAgentFailed() {
        var n = run(state([makeAgent(state: "running")]), state([makeAgent(state: "failed", error: #""boom""#)]))
        XCTAssertEqual(n.count, 1)
        XCTAssertEqual(n.first?.title, "Claude failed")
        XCTAssertEqual(n.first?.body, "boom")
        n = run(state([makeAgent(state: "running")]), state([makeAgent(state: "errored")]))
        XCTAssertEqual(n.first?.body, "The agent stopped with an error")
        XCTAssertTrue(run(state([makeAgent(state: "failed")]), state([makeAgent(state: "failed", updatedAt: 3)])).isEmpty)
    }

    func testTerminalSessionStates() {
        var n = run(state([], [makeSession(state: "running")]), state([], [makeSession(state: "waiting")]))
        XCTAssertEqual(n.count, 1)
        XCTAssertEqual(n.first?.title, "Claude needs your input in the terminal")
        XCTAssertEqual(n.first?.body, "Refactor")
        XCTAssertEqual(n.first?.target, .session("/s/1"))
        n = run(state([], [makeSession(state: "running")]), state([], [makeSession(state: "idle")]))
        XCTAssertEqual(n.first?.title, "Claude finished")
        XCTAssertTrue(run(state(), state([], [makeSession(state: "idle")])).isEmpty)
    }

    func testStaleAndUnknownSessionsAreSilent() {
        for s in ["stale", "unknown"] {
            XCTAssertTrue(run(state([], [makeSession(state: "running")]), state([], [makeSession(state: s)])).isEmpty, "running to \(s)")
            XCTAssertTrue(run(state([], [makeSession(state: s)]), state([], [makeSession(state: "idle")])).isEmpty, "\(s) to idle")
            XCTAssertTrue(run(state([], [makeSession(state: s)]), state([], [makeSession(state: "waiting")])).isEmpty, "\(s) to waiting")
        }
    }

    func testViewedChatIsSilent() {
        XCTAssertTrue(run(state([makeAgent()]), state([makeAgent(pending: pend)]), viewing: .agent("a1")).isEmpty)
        XCTAssertEqual(run(state([makeAgent()]), state([makeAgent(pending: pend)]), viewing: .agent("zz")).count, 1)
        XCTAssertTrue(run(state([], [makeSession(state: "running")]), state([], [makeSession(state: "idle")]),
                          viewing: .session("/s/1")).isEmpty)
    }

    func testBodyIsOneLineAndShort() {
        var n = run(state([], [makeSession(state: "running")]), state([], [makeSession(state: "idle", title: "a\n\n  b\tc\nd")]))
        XCTAssertEqual(n.first?.body, "a b c d")

        let long = String(repeating: "x", count: 500)
        n = run(state([makeAgent(state: "running")]),
                state([makeAgent(state: "idle", messages: #"[{"id":"1","role":"assistant","text":"\#(long)"}]"#)]))
        XCTAssertEqual(n.first?.body.count, 140)
        XCTAssertEqual(n.first?.body.hasSuffix("…"), true)
        XCTAssertEqual(oneLine(String(repeating: "y", count: 140)).count, 140)
    }
}
