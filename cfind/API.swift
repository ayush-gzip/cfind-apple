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

/// A transcript's chat: whole on the first event and after a reconnect, then only
/// the new or changed messages.
enum ChatEvent {
    case chat(Conversation)
    case delta(Conversation)
}

/// Turns the live stream's whole and `-delta` events back into whole values. The
/// Mac sends each snapshot once, then only what changed (context-find src/delta.ts).
struct LiveMerge {
    private(set) var snapshot: Snapshot?
    /// Kept as plain JSON: agent changes are partial and merge before decoding.
    private var workspace: [String: Any]?

    mutating func take(_ event: String, _ data: Data) throws -> LiveEvent? {
        switch event {
        case "metrics":
            let s = try JSONDecoder().decode(Snapshot.self, from: data)
            snapshot = s
            return .metrics(s)
        case "metrics-delta":
            guard var s = snapshot else { return nil }
            // Most deltas only move the clock; the apps redraw for real changes only.
            guard s.apply(try JSONDecoder().decode(MetricsDelta.self, from: data)) else { return nil }
            snapshot = s
            return .metrics(s)
        case "workspace":
            workspace = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return .workspace(try JSONDecoder().decode(Workspace.self, from: data).agents)
        case "workspace-delta":
            guard let w = workspace, let d = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            let next = JSONDelta.apply(w, d)
            workspace = next
            let json = try JSONSerialization.data(withJSONObject: next)
            return .workspace(try JSONDecoder().decode(Workspace.self, from: json).agents)
        default:
            return nil
        }
    }
}

/// The parts of a metrics delta the apps use.
struct MetricsDelta: Decodable {
    struct Fields: Decodable {
        var profiles: [Profile]?
        var sessions: [Session]?
    }
    struct Rows: Decodable {
        var upsert: [Session]?
        var removed: [String]?
    }
    struct Lists: Decodable {
        var sessions: Rows?
    }
    var set: Fields?
    var lists: Lists?
}

extension Snapshot {
    /// False when the delta changed nothing the apps show.
    mutating func apply(_ d: MetricsDelta) -> Bool {
        var changed = false
        if let p = d.set?.profiles {
            profiles = p
            changed = true
        }
        if let all = d.set?.sessions {
            sessions = all
            changed = true
        }
        if let rows = d.lists?.sessions {
            var byPath = Dictionary(sessions.map { ($0.path, $0) }, uniquingKeysWith: { $1 })
            for s in rows.upsert ?? [] { byPath[s.path] = s }
            for path in rows.removed ?? [] { byPath[path] = nil }
            // The Mac's order: newest first, then by path.
            sessions = byPath.values.sorted {
                $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : $0.path < $1.path
            }
            changed = true
        }
        return changed
    }
}

/// The merge from context-find's dashboard/delta.js, on plain JSON. Lists change by
/// key; an agent's change lists only its changed fields (null means removed), and
/// its messages change by id, with streamed text sent as `append`.
enum JSONDelta {
    static func apply(_ snap: [String: Any], _ d: [String: Any]) -> [String: Any] {
        var next = snap
        for (name, value) in d["set"] as? [String: Any] ?? [:] { next[name] = value }
        for (name, list) in d["lists"] as? [String: Any] ?? [:] {
            next[name] = merge(snap[name] as? [[String: Any]] ?? [], list as? [String: Any] ?? [:],
                               nested: name == "agents" ? "messages" : nil)
        }
        return next
    }

    static func key(_ item: [String: Any]) -> String {
        switch item["id"] {
        case let s as String: s
        case let n as NSNumber: n.stringValue
        default: ""
        }
    }

    static func merge(_ list: [[String: Any]], _ d: [String: Any], nested: String?) -> [[String: Any]] {
        var order: [String] = [], byKey: [String: [String: Any]] = [:]
        func put(_ k: String, _ item: [String: Any]) {
            if byKey[k] == nil { order.append(k) }
            byKey[k] = item
        }
        for item in list { put(key(item), item) }
        for item in d["upsert"] as? [[String: Any]] ?? [] {
            let k = key(item)
            guard let old = byKey[k], let nested else {
                put(k, item)
                continue
            }
            var next = old
            for (field, value) in item {
                if value is NSNull {
                    next[field] = nil
                } else if field == nested, let patch = value as? [String: Any] {
                    next[field] = merge(old[field] as? [[String: Any]] ?? [], patch, nested: nil)
                } else {
                    next[field] = value
                }
            }
            byKey[k] = next
        }
        for k in d["removed"] as? [String] ?? [] { byKey[k] = nil }
        for pair in d["append"] as? [[Any]] ?? [] {
            guard pair.count == 2, let k = pair[0] as? String, let text = pair[1] as? String,
                  var m = byKey[k] else { continue }
            m["text"] = (m["text"] as? String ?? "") + text
            byKey[k] = m
        }
        return (d["order"] as? [String] ?? order).compactMap { byKey[$0] }
    }
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

    /// Sessions, limits and dashboard agents, kept whole from the stream's deltas.
    func events() -> AsyncThrowingStream<LiveEvent, Error> {
        stream("api/events", ["delta": "1"]) {
            var merge = LiveMerge()
            return { try merge.take($0, $1) }
        }
    }

    /// A transcript's messages, pushed by the Mac as soon as the file changes.
    func chatEvents(_ path: String) -> AsyncThrowingStream<ChatEvent, Error> {
        stream("api/chat-events", ["path": path]) {
            { event, data in
                switch event {
                case "chat": .chat(try JSONDecoder().decode(Conversation.self, from: data))
                case "chat-delta": .delta(try JSONDecoder().decode(Conversation.self, from: data))
                default: nil
                }
            }
        }
    }

    /// Server-sent events. Each event is one `data:` line; `lines` drops blank
    /// lines, so an event is handled as soon as its data line arrives. `handler`
    /// makes the function that reads each event, once per stream.
    private func stream<T>(_ path: String, _ query: [String: String],
                           _ handler: @escaping () -> (String, Data) throws -> T?) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let handle = handler()
                    let (bytes, response) = try await Self.session.bytes(for: request(path, query))
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        throw http.statusCode == 403
                            ? APIError.unpaired : APIError.server("Live updates failed (\(http.statusCode))")
                    }
                    var event = ""
                    for try await line in bytes.lines {
                        if line.hasPrefix("event: ") {
                            event = String(line.dropFirst(7))
                        } else if line.hasPrefix("data: "), let value = try handle(event, Data(line.utf8.dropFirst(6))) {
                            continuation.yield(value)
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
