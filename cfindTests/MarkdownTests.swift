#if os(iOS)
import XCTest
@testable import cfind

final class MarkdownTests: XCTestCase {
    func describe(_ blocks: [Markdown.Block]) -> [String] {
        blocks.map {
            switch $0 {
            case .text(let t): "text:\(t)"
            case .heading(let h): "heading:\(h)"
            case .code(let l, let c): "code[\(l)]:\(c)"
            }
        }
    }

    func testParagraphsSplitOnBlankLines() {
        XCTAssertEqual(describe(Markdown.blocks("one\ntwo\n\nthree")), ["text:one\ntwo", "text:three"])
    }

    func testHeadings() {
        XCTAssertEqual(describe(Markdown.blocks("# Title\nbody\n###### Small")),
                       ["heading:Title", "text:body", "heading:Small"])
        XCTAssertEqual(describe(Markdown.blocks("#nospace")), ["text:#nospace"])
    }

    func testFencedCode() {
        let text = "before\n```swift\nlet a = 1\n# not a heading\n```\nafter"
        XCTAssertEqual(describe(Markdown.blocks(text)),
                       ["text:before", "code[swift]:let a = 1\n# not a heading", "text:after"])
    }

    func testUnclosedFenceStillEmitsCode() {
        XCTAssertEqual(describe(Markdown.blocks("```\nabc")), ["code[]:abc"])
    }

    func testEmptyText() {
        XCTAssertTrue(Markdown.blocks("").isEmpty)
    }

    func testInlineStylesAndBullets() {
        let bold = Markdown.inline("a **b** c")
        XCTAssertEqual(String(bold.characters), "a b c")
        XCTAssertTrue(bold.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized })
        XCTAssertEqual(String(Markdown.inline("- one\n* two\n  + three").characters), "• one\n• two\n  • three")
    }

    func testInlineKeepsLinks() {
        let s = Markdown.inline("see [docs](https://example.com)")
        XCTAssertEqual(String(s.characters), "see docs")
        XCTAssertEqual(s.runs.compactMap(\.link).first?.absoluteString, "https://example.com")
    }
}
#endif
