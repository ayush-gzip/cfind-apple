import XCTest
@testable import cfind
#if os(macOS)
import CryptoKit
#endif

final class PhonePushTests: XCTestCase {
    func testOpenLinkRoundTrip() {
        let targets: [ChatTarget] = [
            .agent("00000000-1111-2222-3333-444444444444"),
            .session("/Users/me/.claude/projects/-Users-me-My Work/a&b?c=d+e #1 ü.jsonl"),
        ]
        for t in targets {
            XCTAssertEqual(t.link.scheme, "cfind")
            XCTAssertEqual(ChatTarget(link: t.link), t, t.link.absoluteString)
        }
        // Pairing links and other hosts are not chats.
        XCTAssertNil(ChatTarget(link: URL(string: "cfind://pair?url=http://mac:4319&code=123456")!))
        XCTAssertNil(ChatTarget(link: URL(string: "cfind://open?other=x")!))
        XCTAssertNil(ChatTarget(link: URL(string: "cfind://open?agent=")!))
        XCTAssertNil(ChatTarget(link: URL(string: "https://open?agent=x")!))
        XCTAssertNotNil(PairLink(URL(string: "cfind://pair?url=http://mac:4319&code=123456")!))
        XCTAssertNil(PairLink(ChatTarget.agent("x").link))
    }

    #if os(macOS)
    func testRequestIsEncryptedForBark() throws {
        let key = "0123456789abcdefghijklmnopqrstuv", iv = "AbCdEfGhIjKl"
        let link = ChatTarget.session("/p/a b.jsonl").link
        let r = try PhonePush.request(title: "Claude asked you", body: "Go with C? 100% + more", link: link,
                                      url: " https://api.day.app/DEVICE/ ", key: key, iv: iv)
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.url?.absoluteString, "https://api.day.app/DEVICE")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")

        let form = String(decoding: r.httpBody!, as: UTF8.self)
        XCTAssertFalse(form.contains("+"), "base64 + must be encoded: \(form)")
        var fields: [String: String] = [:]
        for pair in form.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding! }
            fields[kv[0]] = kv[1]
        }
        XCTAssertEqual(Set(fields.keys), ["ciphertext", "iv"], "only ciphertext leaves the Mac")
        XCTAssertEqual(fields["iv"], iv)

        // Bark's layout: ciphertext then the 16-byte tag.
        let sealed = try XCTUnwrap(Data(base64Encoded: fields["ciphertext"]!))
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: Data(iv.utf8)),
                                        ciphertext: sealed.dropLast(16), tag: sealed.suffix(16))
        let plain = try AES.GCM.open(box, using: SymmetricKey(data: Data(key.utf8)))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: plain) as? [String: String])
        XCTAssertEqual(json, ["title": "Claude asked you", "body": "Go with C? 100% + more",
                              "group": "cfind", "url": link.absoluteString])
    }

    func testRequestChecksSettings() {
        XCTAssertThrowsError(try PhonePush.request(title: "t", body: "b", link: nil, url: "api.day.app/KEY",
                                                   key: String(repeating: "k", count: 32)))
        for bad in ["short", String(repeating: "k", count: 31), String(repeating: "é", count: 32)] {
            XCTAssertThrowsError(try PhonePush.request(title: "t", body: "b", link: nil,
                                                       url: "https://api.day.app/KEY", key: bad), bad)
        }
        // 16 and 24 characters are AES-128 and AES-192 in Bark.
        XCTAssertNoThrow(try PhonePush.request(title: "t", body: "b", link: nil, url: "https://api.day.app/KEY",
                                               key: String(repeating: "k", count: 16)))
    }

    func testFreshIVs() {
        let ivs = (0..<100).map { _ in PhonePush.randomIV() }
        XCTAssertEqual(Set(ivs).count, 100)
        XCTAssertTrue(ivs.allSatisfy { $0.count == 12 && $0.allSatisfy(\.isASCII) })
    }
    #endif
}
