import Foundation

/// Any JSON value. Approval requests carry tool-specific parameters.
enum JSON: Codable, Hashable {
    case string(String), number(Double), bool(Bool), object([String: JSON]), array([JSON]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    subscript(key: String) -> JSON? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
    var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    var bool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
    var array: [JSON] {
        if case .array(let a) = self { return a }
        return []
    }
    /// Stable text for ids that may be a string or a number.
    var key: String {
        switch self {
        case .string(let s): s
        case .number(let n): String(n)
        default: pretty
        }
    }
    var pretty: String {
        switch self {
        case .object, .array:
            (try? JSONEncoder.pretty.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        default:
            string ?? ""
        }
    }
}

extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()
}

struct Quota: Decodable, Hashable {
    var used: Double
    /// Seconds since 1970.
    var resetsAt: Double

    var left: Int? {
        resetsAt > Date().timeIntervalSince1970 ? Int((100 - used).rounded()) : nil
    }
}

struct Limits: Decodable, Hashable {
    var session: Quota?
    var week: Quota?
    var plan: String?
    var observedAt: Double?
}

struct Profile: Decodable, Identifiable, Hashable {
    var id: String
    var label: String
    var source: String
    var limits: Limits?
}

/// A transcript the Mac watches. Times are milliseconds since 1970. `id` is the
/// tool's session id and can repeat across profiles; `path` is unique.
struct Session: Decodable, Hashable {
    var id: String
    var profile: String
    var source: String
    var path: String
    var cwd: String
    var title: String
    var parent: String?
    var updatedAt: Double
    var state: String
    var open: Bool?
    var tmux: Bool?
}

struct Snapshot: Decodable {
    var profiles: [Profile]
    var sessions: [Session]
}

struct Tool: Decodable, Hashable {
    var name: String
    var input: String
    var output: String?
    var error: Bool?
}

struct Message: Decodable, Identifiable, Hashable {
    var id: String
    var role: String
    var text: String
    var time: Double?
    var tool: Tool?
    /// Data URLs (transcripts) or upload ids (dashboard messages).
    var images: [String]?
}

struct QueueItem: Decodable, Hashable {
    var text: String
    var images: [String]?
}

struct Pending: Decodable, Hashable {
    var id: JSON
    var method: String
    var params: JSON?
}

/// An agent the Mac dashboard runs itself.
struct Agent: Decodable, Identifiable, Hashable {
    var id: String
    var profile: String
    var cwd: String
    var title: String
    var sid: String?
    var history: String?
    var model: String?
    var state: String
    var startedAt: Double
    var updatedAt: Double
    var messages: [Message]
    var queue: [QueueItem]
    var error: String?
    var pending: Pending?
}

struct Workspace: Decodable {
    var agents: [Agent]
}

struct Conversation: Decodable {
    var messages: [Message]
    var omitted: Int
}

let activeStates: Set = ["running", "waiting", "queued"]

func folder(_ path: String) -> String {
    path.split(separator: "/").suffix(2).joined(separator: "/")
}

func age(_ ms: Double) -> String {
    let d = max(0, Date().timeIntervalSince1970 - ms / 1000)
    if d < 60 { return "now" }
    if d < 3600 { return "\(Int(d / 60))m" }
    if d < 86400 { return "\(Int(d / 3600))h" }
    return "\(Int(d / 86400))d"
}

func stateLabel(_ s: String) -> String {
    [
        "idle": "Idle", "running": "Running", "queued": "Queued", "waiting": "Needs input",
        "failed": "Failed", "errored": "Failed", "complete": "Complete", "completed": "Complete",
        "stopped": "Stopped", "stale": "Stale", "unknown": "Unknown",
    ][s] ?? s.capitalized
}

/// A chat to open: a dashboard agent by id, or a transcript by path.
enum ChatTarget: Hashable {
    case agent(String)
    /// A transcript, by path.
    case session(String)
}
