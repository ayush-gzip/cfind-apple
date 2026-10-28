import XCTest
@testable import cfind

/// deltas.json holds frames from context-find's real encoder (ts/src/delta.ts): a whole
/// snapshot, then deltas, each with the snapshot the Mac had at that moment.
final class LiveMergeTests: XCTestCase {
    func testDeltasRebuildTheSnapshot() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "deltas", withExtension: "json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let frames = try XCTUnwrap(root["frames"] as? [[String: Any]])
        var merge = LiveMerge()
        var agents: [Agent]?
        var deltas = 0
        for (i, frame) in frames.enumerated() {
            let event = try XCTUnwrap(frame["event"] as? String)
            let data = try JSONSerialization.data(withJSONObject: try XCTUnwrap(frame["data"]))
            let expect = try JSONSerialization.data(withJSONObject: try XCTUnwrap(frame["expect"]))
            if event.hasSuffix("-delta") { deltas += 1 }
            let out = try merge.take(event, data)
            if event.hasPrefix("metrics") {
                let want = try JSONDecoder().decode(Snapshot.self, from: expect)
                XCTAssertEqual(merge.snapshot?.sessions, want.sessions, "frame \(i)")
                XCTAssertEqual(merge.snapshot?.profiles, want.profiles, "frame \(i)")
                // A delta that only moves the clock does not redraw.
                if frame["quiet"] as? Bool == true { XCTAssertNil(out, "frame \(i)") } else { XCTAssertNotNil(out, "frame \(i)") }
            } else {
                guard case .workspace(let a) = out else { return XCTFail("frame \(i): no agents") }
                agents = a
                XCTAssertEqual(agents, try JSONDecoder().decode(Workspace.self, from: expect).agents, "frame \(i)")
            }
        }
        XCTAssertGreaterThanOrEqual(deltas, 10)
    }

    func testDeltaBeforeSnapshotIsIgnored() throws {
        var merge = LiveMerge()
        XCTAssertNil(try merge.take("metrics-delta", Data(#"{"set":{"updatedAt":2}}"#.utf8)))
        XCTAssertNil(try merge.take("workspace-delta", Data(#"{"lists":{"agents":{"removed":["a"]}}}"#.utf8)))
        XCTAssertNil(merge.snapshot)
    }

    func testTokenAppendsToTheMessage() throws {
        var merge = LiveMerge()
        let agent = #"{"id":"a","profile":"p","cwd":"/x","title":"t","state":"running","startedAt":0,"updatedAt":1,"messages":[{"id":"m","role":"assistant","text":"Hel"}],"queue":[]}"#
        _ = try merge.take("workspace", Data(#"{"agents":[\#(agent)]}"#.utf8))
        let out = try merge.take("workspace-delta", Data(#"{"lists":{"agents":{"upsert":[{"id":"a","messages":{"append":[["m","lo"]]}}]}}}"#.utf8))
        guard case .workspace(let agents) = out else { return XCTFail("no agents") }
        XCTAssertEqual(agents.first?.messages.first?.text, "Hello")
    }

    func testChatDeltaReplacesInPlaceAndAppends() {
        let msg = { (id: String, text: String) in Message(id: id, role: "assistant", text: text) }
        let out = Conversation.merge([msg("1", "a"), msg("2", "b")], [msg("2", "b2"), msg("3", "c")])
        XCTAssertEqual(out.map(\.id), ["1", "2", "3"])
        XCTAssertEqual(out.map(\.text), ["a", "b2", "c"])
        XCTAssertEqual(Conversation.merge(out, [msg("4", "d")], keep: 2).map(\.id), ["3", "4"])
    }
}
