import Foundation
import Security

/// The Mac this iPhone is paired with, and the device token it was given.
struct Pairing: Codable, Equatable {
    var base: URL
    var token: String
}

/// A `cfind://pair?url=…&code=…` link from the Mac dashboard.
struct PairLink: Equatable {
    var base: URL
    var code: String

    init?(_ url: URL) {
        guard url.scheme == "cfind", url.host() == "pair",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == "url" })?.value,
              let base = URL(string: raw), ["http", "https"].contains(base.scheme ?? ""),
              let code = items.first(where: { $0.name == "code" })?.value
        else { return nil }
        self.base = base
        self.code = code
    }
}

enum APIError: LocalizedError {
    case server(String)
    case unpaired

    var errorDescription: String? {
        switch self {
        case .server(let message): message
        case .unpaired: "This iPhone is no longer paired. Pair it again from the Mac."
        }
    }
}

enum LiveEvent {
    case metrics(Snapshot)
    case workspace([Agent])
}

struct API {
    let pairing: Pairing

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        // The live stream sends a heartbeat every 15 seconds.
        c.timeoutIntervalForRequest = 60
        return URLSession(configuration: c)
    }()

    func request(_ path: String, _ query: [String: String] = [:], method: String = "GET",
                 body: Data? = nil, type: String? = nil) -> URLRequest {
        var c = URLComponents(url: pairing.base.appending(path: path), resolvingAgainstBaseURL: false)!
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        #if os(macOS)
        items.append(URLQueryItem(name: "t", value: pairing.token))
        #endif
        if !items.isEmpty { c.queryItems = items }
        var r = URLRequest(url: c.url!)
        r.httpMethod = method
        r.httpBody = body
        #if os(iOS)
        r.setValue("Bearer \(pairing.token)", forHTTPHeaderField: "Authorization")
        #endif
        if let type { r.setValue(type, forHTTPHeaderField: "Content-Type") }
        return r
    }

    static func check(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.server("No response from the Mac") }
        if (200..<300).contains(http.statusCode) { return }
        let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
        if http.statusCode == 403 && message == "forbidden" { throw APIError.unpaired }
        throw APIError.server(message ?? "Request failed (\(http.statusCode))")
    }

    func get<T: Decodable>(_ path: String, _ query: [String: String] = [:]) async throws -> T {
        let (data, response) = try await Self.session.data(for: request(path, query))
        try Self.check(data, response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Agent actions. A dropped connection is retried with the same client id, and
    /// the Mac runs a client id only once, so a retry never sends twice.
    func agentData(_ body: [String: Any]) async throws -> Data {
        var body = body
        body["clientId"] = UUID().uuidString
        let payload = try JSONSerialization.data(withJSONObject: body)
        var attempt = 0
        while true {
            do {
                let (data, response) = try await Self.session.data(
                    for: request("api/agent", method: "POST", body: payload, type: "application/json"))
                try Self.check(data, response)
                return data
            } catch let e as URLError where attempt < 2 && [.networkConnectionLost, .timedOut].contains(e.code) {
                attempt += 1
                try await Task.sleep(for: .seconds(attempt))
            }
        }
    }

    @discardableResult
    func agent(_ body: [String: Any]) async throws -> JSON {
        try JSONDecoder().decode(JSON.self, from: try await agentData(body))
    }

    func upload(_ data: Data, type: String) async throws -> String {
        let (out, response) = try await Self.session.data(
            for: request("api/upload", method: "POST", body: data, type: type))
        try Self.check(out, response)
        guard let id = try JSONDecoder().decode([String: String].self, from: out)["id"] else {
            throw APIError.server("Upload failed")
        }
        return id
    }

    /// Full-text search over transcripts on the Mac, best first. Remote hosts are skipped.
    func search(_ q: String) async throws -> [String] {
        struct Row: Decodable { var path: String; var host: String? }
        struct Found: Decodable { var sessions: [Row] }
        let found: Found = try await get("api/search", ["q": q])
        return found.sessions.filter { $0.host == nil }.map(\.path)
    }

    func image(_ id: String) async throws -> Data {
        let (data, response) = try await Self.session.data(for: request("api/upload", ["id": id]))
        try Self.check(data, response)
        return data
    }

    static func pair(base: URL, code: String, name: String) async throws -> Pairing {
        var r = URLRequest(url: base.appending(path: "api/pair"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["code": code, "name": name])
        let (data, response) = try await session.data(for: r)
        try check(data, response)
        guard let token = try JSONDecoder().decode([String: String].self, from: data)["token"] else {
            throw APIError.server("Pairing failed")
        }
        return Pairing(base: base, token: token)
    }

    func unpair() async throws {
        let body = try JSONSerialization.data(withJSONObject: ["action": "unpair"])
        let (data, response) = try await Self.session.data(
            for: request("api/pair", method: "POST", body: body, type: "application/json"))
        try Self.check(data, response)
    }

    /// Server-sent events. Each event is one `data:` line; `lines` drops blank
    /// lines, so an event is handled as soon as its data line arrives.
    func events() -> AsyncThrowingStream<LiveEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await Self.session.bytes(for: request("api/events"))
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        throw http.statusCode == 403
                            ? APIError.unpaired : APIError.server("Live updates failed (\(http.statusCode))")
                    }
                    var event = ""
                    for try await line in bytes.lines {
                        if line.hasPrefix("event: ") {
                            event = String(line.dropFirst(7))
                        } else if line.hasPrefix("data: ") {
                            let data = Data(line.utf8.dropFirst(6))
                            if event == "metrics" {
                                continuation.yield(.metrics(try JSONDecoder().decode(Snapshot.self, from: data)))
                            } else if event == "workspace" {
                                continuation.yield(.workspace(try JSONDecoder().decode(Workspace.self, from: data).agents))
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

#if os(macOS)
/// The daemon on this Mac writes its port and token here. The token goes in the URL as `t`.
enum ServiceFile {
    static func load() -> Pairing? {
        struct Service: Decodable { var port: Int; var token: String }
        let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".context-find/dashboard/service.json")
        guard let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Service.self, from: data),
              let base = URL(string: "http://127.0.0.1:\(s.port)")
        else { return nil }
        return Pairing(base: base, token: s.token)
    }
}
#else
/// The pairing lives in the Keychain, on this device only.
enum Keychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "cfind.pairing",
    ]

    static func load() -> Pairing? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(Pairing.self, from: data)
    }

    static func save(_ pairing: Pairing) {
        delete()
        var q = query
        q[kSecValueData as String] = try? JSONEncoder().encode(pairing)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
#endif
