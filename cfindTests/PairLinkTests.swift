#if os(iOS)
import XCTest
@testable import cfind

final class PairLinkTests: XCTestCase {
    func link(_ s: String) -> PairLink? { URL(string: s).flatMap(PairLink.init) }

    func testValidLink() {
        let l = link("cfind://pair?url=https%3A%2F%2Fmac.tailnet.ts.net&code=123456")
        XCTAssertEqual(l?.base.absoluteString, "https://mac.tailnet.ts.net")
        XCTAssertEqual(l?.code, "123456")
    }

    func testHttpIsAccepted() {
        XCTAssertEqual(link("cfind://pair?url=http%3A%2F%2F127.0.0.1%3A4319&code=1")?.base.port, 4319)
    }

    func testRejectsBadLinks() {
        XCTAssertNil(link("https://pair?url=https%3A%2F%2Fa.b&code=1"))
        XCTAssertNil(link("cfind://other?url=https%3A%2F%2Fa.b&code=1"))
        XCTAssertNil(link("cfind://pair?url=ftp%3A%2F%2Fa.b&code=1"))
        XCTAssertNil(link("cfind://pair?url=https%3A%2F%2Fa.b"))
        XCTAssertNil(link("cfind://pair?code=1"))
        XCTAssertNil(link("cfind://pair?url=not-a-url&code=1"))
    }
}
#endif
