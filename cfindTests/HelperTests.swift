import XCTest
@testable import cfind

final class HelperTests: XCTestCase {
    func testFolderKeepsLastTwoParts() {
        XCTAssertEqual(folder("/Users/me/code/cfind"), "code/cfind")
        XCTAssertEqual(folder("/cfind"), "cfind")
        XCTAssertEqual(folder("/"), "")
    }

    func testAge() {
        let now = Date().timeIntervalSince1970 * 1000
        XCTAssertEqual(age(now), "now")
        XCTAssertEqual(age(now + 60_000), "now")
        XCTAssertEqual(age(now - 5 * 60_000), "5m")
        XCTAssertEqual(age(now - 3 * 3_600_000), "3h")
        XCTAssertEqual(age(now - 2 * 86_400_000), "2d")
    }

    func testStateLabel() {
        XCTAssertEqual(stateLabel("waiting"), "Needs input")
        XCTAssertEqual(stateLabel("errored"), "Failed")
        XCTAssertEqual(stateLabel("completed"), "Complete")
        XCTAssertEqual(stateLabel("something"), "Something")
    }

    func testOneLine() {
        XCTAssertEqual(oneLine("  a \n b\t\tc  "), "a b c")
        XCTAssertEqual(oneLine(""), "")
    }

    func testQuotaLeft() throws {
        let future = Date().timeIntervalSince1970 + 3600
        XCTAssertEqual(try decode(Quota.self, #"{"used":30.4,"resetsAt":\#(future)}"#).left, 70)
        XCTAssertNil(try decode(Quota.self, #"{"used":30,"resetsAt":1}"#).left)
    }

    func testJSONKeyAndPretty() throws {
        XCTAssertEqual(JSON.string("abc").key, "abc")
        XCTAssertEqual(JSON.number(5).key, "5.0")
        let j = try decode(JSON.self, #"{"a":[1,"x",null,true],"b":{"c":"d"}}"#)
        XCTAssertEqual(j["b"]?["c"]?.string, "d")
        XCTAssertEqual(j["a"]?.array.count, 4)
        XCTAssertEqual(j["a"]?.array[3].bool, true)
        XCTAssertNil(j["missing"])
        XCTAssertTrue(j.pretty.contains("\"c\" : \"d\""))
    }
}
