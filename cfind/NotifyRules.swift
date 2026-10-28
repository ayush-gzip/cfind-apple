import Foundation

/// The chat a notification is about. Mirrors `ChatTarget`, which lives with the views.
enum NotifyTarget: Hashable {
    case agent(String)
    case session(String)
}

struct Note: Equatable {
    var id: String
    var title: String
    var body: String
    var target: NotifyTarget
}

/// Last known state per target. Sessions are the ones worth watching: open in a
/// terminal, not a sub-session, not covered by a dashboard agent.
struct NotifyState {
    var agents: [String: Agent]
    var sessions: [String: Session]

    init(agents: [Agent], sessions: [Session]) {
        self.agents = Dictionary(agents.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        self.sessions = Dictionary(sessions.map { ($0.path, $0) }, uniquingKeysWith: { $1 })
    }
}

private let running: Set = ["running", "queued"]
private let finished: Set = ["idle", "complete", "completed"]
private let failed: Set = ["failed", "errored"]

/// `old == nil` is the first update after connecting: it only sets the baseline.
func notes(old: NotifyState?, new: NotifyState, viewing: NotifyTarget?, agentName: (String) -> String) -> [Note] {
    guard let old else { return [] }
    var out: [Note] = []

    for (id, a) in new.agents.sorted(by: { $0.key < $1.key }) {
        guard let was = old.agents[id], viewing != .agent(id) else { continue }
        let target = NotifyTarget.agent(id)
        if was.pending == nil, let p = a.pending {
            out.append(Note(id: "agent:\(id):pending:\(p.id.key)", title: "\(agentName(a.profile)) needs your input",
                            body: oneLine("\(a.title): \(ask(p))"), target: target))
        } else if a.pending == nil, a.state == "idle", let q = a.ask, running.contains(was.state) || was.ask != q {
            // Same id as the "replied" note of this turn, so a late ask replaces it.
            out.append(Note(id: "agent:\(id):done:\(a.updatedAt)", title: "\(agentName(a.profile)) asked you",
                            body: oneLine(q), target: target))
        } else if running.contains(was.state), finished.contains(a.state), a.pending == nil {
            let reply = a.messages.last { $0.role != "user" && $0.tool == nil && !$0.text.isEmpty }?.text
            out.append(Note(id: "agent:\(id):done:\(a.updatedAt)", title: "\(agentName(a.profile)) replied",
                            body: oneLine(reply ?? a.title), target: target))
        } else if failed.contains(a.state), !failed.contains(was.state) {
            out.append(Note(id: "agent:\(id):failed:\(a.updatedAt)", title: "\(agentName(a.profile)) failed",
                            body: oneLine(a.error ?? "The agent stopped with an error"), target: target))
        }
    }

    for (path, s) in new.sessions.sorted(by: { $0.key < $1.key }) {
        guard let was = old.sessions[path], viewing != .session(path) else { continue }
        let name = agentName(s.profile)
        let title: String, body: String
        // The ask can show up one poll after the state flips to idle.
        if s.state == "idle", let q = s.ask, was.state == "running" || was.ask != q {
            title = "\(name) asked you"
            body = q
        } else if was.state == "running" {
            switch s.state {
            case "waiting": title = "\(name) needs your input in the terminal"
            case "idle": title = "\(name) finished"
            default: continue
            }
            body = s.title
        } else {
            continue
        }
        // Same id as the "finished" note of this turn, so a late ask replaces it.
        out.append(Note(id: "session:\(path):\(s.state):\(s.updatedAt)", title: title, body: oneLine(body),
                        target: .session(path)))
    }
    return out
}

private func ask(_ p: Pending) -> String {
    let params = p.params
    switch p.method {
    case "can_use_tool":
        if params?["tool_name"]?.string == "AskUserQuestion",
           let q = params?["input"]?["questions"]?.array.first?["question"]?.string { return q }
        return params?["display_name"]?.string ?? params?["tool_name"]?.string ?? "a request"
    case "item/commandExecution/requestApproval":
        return params?["command"]?.string ?? "a command"
    case "item/fileChange/requestApproval":
        return "file changes"
    default:
        return params?["questions"]?.array.first?["question"]?.string ?? "a request"
    }
}

/// One line, at most 140 characters.
func oneLine(_ s: String) -> String {
    let t = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return t.count > 140 ? t.prefix(139) + "…" : t
}
