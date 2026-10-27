#if os(iOS)
import SwiftUI

struct SessionsView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var profile = "all"
    /// Paths that match in the message text, after "Search message text".
    @State private var found: [String]?
    @State private var searching = false
    @State private var searchError: String?

    var body: some View {
        let all = sessions
        // Open in a terminal counts as active even when idle.
        let live = { (s: Session) in activeStates.contains(s.state) || s.open == true }
        let active = all.filter(live)
        TabStack {
            ChatList {
                ConnectionRow()
                if let found {
                    let byPath = Dictionary((model.snapshot?.sessions ?? []).map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
                    let hits = found.compactMap { byPath[$0] }.filter { $0.parent == nil && (profile == "all" || $0.profile == profile) }
                    Section("Message text") {
                        if hits.isEmpty { Text("No matches").foregroundStyle(.secondary) }
                        ForEach(hits, id: \.path, content: row)
                    }
                } else {
                    if !search.isEmpty {
                        Button {
                            Task { await fullText() }
                        } label: {
                            HStack {
                                Label("Search message text", systemImage: "text.magnifyingglass")
                                if searching { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(searching)
                        if let searchError { Text(searchError).foregroundStyle(.red) }
                    }
                    if !active.isEmpty {
                        Section("Active") {
                            ForEach(active, id: \.path) { s in
                                row(s)
                                SubagentRows(parent: s.id, profile: s.profile, state: s.state)
                            }
                        }
                    }
                    Section("Recent") {
                        ForEach(all.filter { !live($0) }.prefix(200), id: \.path, content: row)
                    }
                }
            }
            .searchable(text: $search, placement: .sessions, prompt: "Search sessions")
            .onSubmit(of: .search) { Task { await fullText() } }
            .onChange(of: search) {
                found = nil
                searchError = nil
            }
            .navigationTitle("Sessions")
            .toolbar {
                Menu {
                    Picker("Profile", selection: $profile) {
                        Text("All profiles").tag("all")
                        ForEach(model.snapshot?.profiles ?? []) { Text($0.label).tag($0.id) }
                    }
                } label: {
                    Image(systemName: profile == "all" ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
    }

    var sessions: [Session] {
        (model.snapshot?.sessions ?? []).filter {
            $0.parent == nil && (profile == "all" || $0.profile == profile)
                && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
                    || $0.cwd.localizedCaseInsensitiveContains(search))
        }
    }

    /// The same search as the website: the Mac scans every transcript's text.
    func fullText() async {
        guard let api = model.api, !search.isEmpty else { return }
        searching = true
        defer { searching = false }
        do {
            found = try await api.search(search)
        } catch {
            searchError = error.localizedDescription
        }
    }

    func row(_ s: Session) -> some View {
        ChatLink(target: model.agent(for: s).map { ChatTarget.agent($0.id) } ?? .session(s.path)) {
            RowLabel(title: s.title, state: s.state, profile: s.profile, cwd: s.cwd, updatedAt: s.updatedAt)
        }
    }
}

struct AgentsView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [ChatTarget] = []
    @State private var creating = false

    var body: some View {
        TabStack(path: $path) {
            ChatList {
                ConnectionRow()
                let all = items
                if all.isEmpty {
                    Text("No agents yet. Start one, or continue a session from Sessions.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Self.lanes.indices, id: \.self) { lane in
                    let group = all.filter { Self.lane($0.state) == lane }
                    if !group.isEmpty {
                        Section(Self.lanes[lane]) {
                            ForEach(group) { a in
                                row(a)
                                SubagentRows(parent: a.parent, profile: a.profile, state: a.state)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Agents")
            .toolbar {
                Button {
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("new-agent")
                .disabled(model.snapshot == nil)
            }
            .sheet(isPresented: $creating) {
                NewAgentView { id in path.append(.agent(id)) }
            }
        }
    }

    /// A dashboard agent, or a session open in a terminal (as on the website board).
    struct Item: Identifiable {
        var id: ChatTarget
        var title: String
        var state: String
        var profile: String
        var cwd: String
        var updatedAt: Double
        var terminal: Bool
        /// The id its subagents name as `parent`.
        var parent: String?
    }

    static let lanes = ["Needs input", "Running", "Queued", "Idle"]
    static func lane(_ state: String) -> Int {
        switch state {
        case "waiting": 0
        case "running", "stale": 1
        case "queued": 2
        default: 3
        }
    }

    var items: [Item] {
        let owned = model.agents.map {
            Item(id: .agent($0.id), title: $0.title, state: $0.pending != nil ? "waiting" : $0.state,
                 profile: $0.profile, cwd: $0.cwd, updatedAt: $0.updatedAt, terminal: false, parent: $0.sid)
        }
        let open = (model.snapshot?.sessions ?? []).filter {
            $0.parent == nil && model.agent(for: $0) == nil
                && ($0.open == true || ["running", "waiting", "stale"].contains($0.state))
        }.map {
            Item(id: .session($0.path), title: $0.title, state: $0.state, profile: $0.profile,
                 cwd: $0.cwd, updatedAt: $0.updatedAt, terminal: true, parent: $0.id)
        }
        return owned + open
    }

    func row(_ a: Item) -> some View {
        ChatLink(target: a.id) {
            RowLabel(title: a.title, state: a.state, profile: a.profile, cwd: a.cwd,
                     updatedAt: a.updatedAt, terminal: a.terminal)
        }
    }
}

struct NewAgentView: View {
    var started: (String) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var profile = ""
    @State private var cwd = ""
    @State private var prompt = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Profile", selection: $profile) {
                    ForEach(model.snapshot?.profiles ?? []) { Text($0.label).tag($0.id) }
                }
                Section("Project folder") {
                    TextField("Folder on the Mac", text: $cwd)
                        .noAutocapitalization()
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("new-folder")
                }
                Section("Task") {
                    TextField("What should it do?", text: $prompt, axis: .vertical)
                        .lineLimit(3...10)
                        .accessibilityIdentifier("new-prompt")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("New agent")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { Task { await start() } }
                        .disabled(busy || profile.isEmpty || cwd.isEmpty || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("start-agent")
                }
            }
            .onAppear {
                let profiles = model.snapshot?.profiles ?? []
                profile = profiles.first { $0.id == "claude" }?.id ?? profiles.first?.id ?? ""
                cwd = model.snapshot?.sessions.first?.cwd ?? ""
            }
        }
    }

    func start() async {
        guard let api = model.api else { return }
        busy = true
        defer { busy = false }
        do {
            let data = try await api.agentData(["action": "create", "profile": profile, "cwd": cwd, "prompt": prompt])
            let agent = try JSONDecoder().decode(Agent.self, from: data)
            if !model.agents.contains(where: { $0.id == agent.id }) { model.agents.insert(agent, at: 0) }
            dismiss()
            started(agent.id)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct UsageView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabStack {
            ChatList {
                ConnectionRow()
                ForEach(model.snapshot?.profiles ?? []) { p in
                    Section {
                        quota("Session", p.limits?.session)
                        quota("Week", p.limits?.week)
                    } header: {
                        HStack(spacing: 7) {
                            Image(p.source == "codex" ? "CodexMark" : "ClaudeMark")
                                .resizable()
                                .frame(width: 17, height: 17)
                                .foregroundStyle(profileColor(p.id))
                            Text(p.label)
                            Spacer()
                            if let plan = p.limits?.plan { Text(plan) }
                        }
                    }
                }
            }
            .navigationTitle("Usage")
        }
    }

    func quota(_ name: String, _ q: Quota?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                Spacer()
                Text(q?.left.map { "\($0)% left" } ?? "Not available").foregroundStyle(.secondary)
            }
            ProgressView(value: Double(q?.left ?? 0), total: 100)
            if let q, q.left != nil {
                Text("Resets \(Date(timeIntervalSince1970: q.resetsAt), style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct MacView: View {
    @Environment(AppModel.self) private var model
    @State private var confirm = false

    var body: some View {
        NavigationStack {
            List {
                Section("Paired Mac") {
                    LabeledContent("Address", value: model.pairing?.base.host() ?? "")
                    LabeledContent("Status", value: model.connected ? "Connected" : (model.problem ?? "Connecting…"))
                }
                Section {
                    Button("Unpair this iPhone", role: .destructive) { confirm = true }
                } footer: {
                    Text("The Mac forgets this iPhone. You can also remove it on the Mac under Connections.")
                }
            }
            .navigationTitle("Mac")
            .confirmationDialog("Unpair this iPhone?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Unpair", role: .destructive) { Task { await model.unpair() } }
            }
        }
    }
}


/// Profile colours, the same as the website.
func profileColor(_ profile: String) -> Color {
    switch profile {
    case "codex": Color(red: 0.34, green: 0.48, blue: 0.90)
    case "personal": Color(red: 0.63, green: 0.48, blue: 0.82)
    default: Color(red: 0.84, green: 0.48, blue: 0.34)
    }
}
#endif
