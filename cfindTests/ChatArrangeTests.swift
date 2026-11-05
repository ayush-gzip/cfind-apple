#if os(iOS)
import XCTest
@testable import cfind

final class ChatArrangeTests: XCTestCase {
    func item(_ id: String, _ role: String, minute: Double) -> ChatItem {
        ChatItem(id: id, kind: .message(Message(id: id, role: role, text: id, time: minute * 60_000)))
    }

    /// "time" rows, and each bubble as id + F (first of its run) + L (last of its run).
    func describe(_ items: [ChatItem]) -> [String] {
        items.map { item in
            switch item.kind {
            case .time: "time"
            case .message(let m) where m.role == "tool": m.id
            default: item.id + (item.first ? "F" : "") + (item.last ? "L" : "")
            }
        }
    }

    func testRunsAndTimeLines() {
        let items = [
            item("u1", "user", minute: 0),
            item("a1", "assistant", minute: 1),
            item("a2", "assistant", minute: 2),
            item("t1", "tool", minute: 3),
            item("a3", "assistant", minute: 4),
            // 20 minutes later: a time line goes over it.
            item("u2", "user", minute: 24),
            item("u3", "user", minute: 25),
            item("a4", "assistant", minute: 26),
        ]
        XCTAssertEqual(describe(ChatView.arrange(items)),
                       ["time", "u1FL", "a1F", "a2L", "t1", "a3FL", "time", "u2F", "u3L", "a4FL"])
    }

    func testNoTimeLineWithoutTimes() {
        let items = [ChatItem(id: "n", kind: .note("Opening conversation…"))]
        XCTAssertEqual(describe(ChatView.arrange(items)), ["nFL"])
    }
}
#endif
