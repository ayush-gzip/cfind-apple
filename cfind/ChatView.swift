#if os(iOS)
import PhotosUI
import SwiftUI

struct ChatItem: Identifiable {
    enum Kind {
        case message(Message)
        case note(String)
        case typing
        case queued(Int, QueueItem)
        case error(String)
        case pending(Agent)
    }

    let id: String
    let kind: Kind
}

/// What the message box can do for this chat; mirrors the web dashboard.
struct ComposerState {
    var enabled: Bool
    var placeholder: String
    var hint: String
    var stop = false
    var live = false
    var takeover = false
    var decline = false
}

struct Attachment {
    let key = UUID()
    var image: PlatformImage
    var uploadId: String?
}

struct ChatView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var current: ChatTarget
    @State private var history: [Message] = []
    @State private var omitted = 0
    @State private var loading = true
    @State private var loadError: String?
    @State private var draft = ""
    @State private var picks: [PhotosPickerItem] = []
    @State private var attachments: [Attachment] = []
    @State private var sending = false
    @State private var error: String?
    @State private var toast: String?
    @State private var atBottom = true
    @State private var confirmTakeover = false

    init(target: ChatTarget) {
        _current = State(initialValue: target)
    }

    var agent: Agent? {
        if case .agent(let id) = current { return model.agents.first { $0.id == id } }
        return nil
    }

    var session: Session? {
        if case .session(let path) = current { return model.snapshot?.sessions.first { $0.path == path } }
        return nil
    }

    var transcript: String? {
        if case .session(let path) = current { return path }
        return agent?.history
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(items) { item in
                        itemView(item, proxy: proxy).id(item.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                        .onAppear { atBottom = true }
                        .onDisappear { atBottom = false }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: signature) {
                if atBottom { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            .safeAreaInset(edge: .bottom) { composer(proxy) }
        }
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 5) {
                        StateDot(state: state)
                        Text(stateLabel(state))
                        if !profileID.isEmpty { ProfileTag(profile: profileID) }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) { menu }
        }
        .confirmationDialog("Stop it in the terminal?", isPresented: $confirmTakeover, titleVisibility: .visible) {
            Button("Take over", role: .destructive) { Task { await takeOver() } }
        } message: {
            Text("The terminal session stops, then the conversation continues here.")
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { self.toast = nil }
                    }
            }
        }
        .task(id: transcript) { await follow() }
    }

    var title: String { agent?.title ?? session?.title ?? "Conversation" }
    var profileID: String { agent?.profile ?? session?.profile ?? "" }
    var state: String { agent.map { $0.pending != nil ? "waiting" : $0.state } ?? session?.state ?? "idle" }

    @ViewBuilder var menu: some View {
        let c = composerState
        if c.takeover {
            Button("Take over") { confirmTakeover = true }
        } else if let a = agent, !activeStates.contains(a.state) {
            Menu {
                Button("Remove card", systemImage: "trash", role: .destructive) {
                    Task {
                        try? await model.api?.agent(["action": "dismiss", "id": a.id])
                        dismiss()
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    /// Reloads the transcript when the Mac reports a change, at most every 2.5 s.
    func follow() async {
        guard let path = transcript, let api = model.api else {
            loading = false
            return
        }
        var loadedAt: Double?
        while !Task.isCancelled {
            let stamp = session?.updatedAt ?? 0
            if loadedAt == nil || (session != nil && stamp != loadedAt) {
                do {
                    let c: Conversation = try await api.get("api/conversation", ["path": path])
                    history = c.messages
                    omitted = c.omitted
                    loadError = nil
                } catch {
                    if !Task.isCancelled { loadError = error.localizedDescription }
                }
                loading = false
                loadedAt = stamp
                // A dashboard agent's own messages arrive live; its history is fixed.
                if session == nil { return }
            }
            try? await Task.sleep(for: .seconds(2.5))
        }
    }

    var items: [ChatItem] {
        var out: [ChatItem] = []
        if omitted > 0 { out.append(.init(id: "omitted", kind: .note("\(omitted) earlier messages are not shown"))) }
        let a = agent
        let past = a.map { a in history.filter { ($0.time ?? 0) < a.startedAt } } ?? history
        out += past.map { .init(id: "h:" + $0.id, kind: .message($0)) }
        if let a {
            if !past.isEmpty { out.append(.init(id: "continued", kind: .note("Continued from the dashboard"))) }
            out += a.messages.map { .init(id: "m:" + $0.id, kind: .message($0)) }
            if ["running", "queued"].contains(a.state) && a.pending == nil { out.append(.init(id: "typing", kind: .typing)) }
            out += a.queue.enumerated().map { .init(id: "q:\($0.offset)", kind: .queued($0.offset, $0.element)) }
            if let e = a.error { out.append(.init(id: "error", kind: .error(e))) }
            if let p = a.pending { out.append(.init(id: "pending:" + p.id.key, kind: .pending(a))) }
        }
        if let loadError { out.append(.init(id: "load-error", kind: .error(loadError))) }
        if out.isEmpty { out.append(.init(id: "empty", kind: .note(loading ? "Opening conversation…" : "No messages yet"))) }
        return out
    }

    var signature: String {
        "\(items.count):\(items.last?.id ?? ""):\(agent?.messages.last?.text.count ?? 0):\(history.last?.text.count ?? 0)"
    }

    @ViewBuilder
    func itemView(_ item: ChatItem, proxy: ScrollViewProxy) -> some View {
        switch item.kind {
        case .message(let m) where m.role == "tool":
            ToolRow(message: m) {
                // Bring an opened tool into view when it opened near the end.
                guard atBottom else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    withAnimation { proxy.scrollTo(item.id, anchor: .top) }
                }
            }
        case .message(let m) where m.role == "note":
            NoteRow(text: m.text)
        case .message(let m):
            Bubble(message: m, user: m.role == "user", label: model.label(agent?.profile ?? session?.profile ?? ""))
        case .note(let text):
            NoteRow(text: text)
        case .typing:
            TypingBubble()
        case .queued(let index, let q):
            VStack(alignment: .trailing, spacing: 4) {
                Bubble(message: Message(id: "q", role: "user", text: q.text, images: q.images), user: true, label: "", queued: true)
                Button("Remove from queue", role: .destructive) {
                    Task { try? await model.api?.agent(["action": "unqueue", "id": agent?.id ?? "", "index": index]) }
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        case .error(let text):
            Text(text)
                .font(.footnote)
                .foregroundStyle(.red)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        case .pending(let a):
            PendingCard(agent: a)
        }
    }

    var composerState: ComposerState {
        if let a = agent {
            let name = model.agentName(a.profile)
            let decline = a.pending?.method == "can_use_tool" && a.pending?.params?["tool_name"]?.string != "AskUserQuestion"
            return ComposerState(
                enabled: true,
                placeholder: decline ? "Decline and tell \(name) what to do instead…"
                    : a.state == "running" ? "Queue a follow-up…" : "Message \(name)…",
                hint: a.state == "running" ? "Messages wait until the current reply ends." : "",
                stop: activeStates.contains(a.state),
                decline: decline)
        }
        guard let s = session else { return ComposerState(enabled: false, placeholder: "Read only", hint: "") }
        let label = model.label(s.profile), idle = s.state == "idle", local = s.parent == nil
        // The Mac checks who has the file open: the Codex helper, another window, or nobody.
        if local && s.source == "codex" {
            return ["running", "waiting"].contains(s.state)
                ? ComposerState(enabled: true, placeholder: "Queue a message for \(label)…", hint: "Runs after the current reply")
                : ComposerState(enabled: true, placeholder: "Continue this conversation…",
                                hint: "Sends to \(label) if it is open, or continues on the Mac")
        }
        if local && s.open == true && s.tmux == true && (idle || s.state == "running") {
            return ComposerState(
                enabled: true,
                placeholder: idle ? "Message \(label) in its terminal…" : "Message \(label) while it works…",
                hint: idle ? "Types into its tmux pane" : "Claude reads this before it finishes",
                live: true)
        }
        let reason: String? =
            s.parent != nil ? "Subagent transcripts are read-only."
            : s.open == true && s.tmux == true
                ? (s.state == "waiting" ? "Waiting for an answer in its terminal. Answer there." : "Its state is unclear. Reply in its terminal.")
            : s.open == true && idle ? "Open in a terminal outside tmux. Reply there, or take over to continue here."
            : s.open == true || ["running", "waiting", "stale"].contains(s.state)
                ? "Open in another window. Reply there, or quit it there to continue here."
            : nil
        if let reason {
            return ComposerState(enabled: false, placeholder: "Read only", hint: reason,
                                 takeover: local && s.open == true && s.tmux != true && idle)
        }
        return ComposerState(enabled: true, placeholder: "Continue this conversation…",
                             hint: "Continues with \(label) in \(folder(s.cwd))")
    }

    func composer(_ proxy: ScrollViewProxy) -> some View {
        let c = composerState
        return VStack(spacing: 6) {
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture { self.error = nil }
            }
            if !attachments.isEmpty { attachmentStrip }
            HStack(alignment: .bottom, spacing: 8) {
                if c.enabled {
                    PhotosPicker(selection: $picks, maxSelectionCount: max(1, 4 - attachments.count), matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 19))
                            .frame(width: 34, height: 36)
                    }
                    .disabled(attachments.count >= 4 || c.decline)
                }
                TextField(c.placeholder, text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .disabled(!c.enabled)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 19))
                    .accessibilityIdentifier("composer")
                if c.stop, let a = agent {
                    Button {
                        Task { try? await model.api?.agent(["action": "cancel", "id": a.id]) }
                    } label: {
                        Image(systemName: "stop.circle.fill").font(.system(size: 31))
                    }
                    .tint(.primary)
                    .accessibilityLabel("Stop")
                }
                if c.enabled {
                    Button {
                        Task { await send(c) }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 31))
                    }
                    .disabled(canNotSend)
                    .accessibilityLabel("Send")
                    .accessibilityIdentifier("send")
                }
            }
            if !c.hint.isEmpty {
                Text(c.hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, c.enabled ? 46 : 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.bar)
        .onChange(of: picks) { _, items in
            guard !items.isEmpty else { return }
            picks = []
            Task { await attach(items) }
        }
    }

    var canNotSend: Bool {
        sending || (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)
    }

    var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments, id: \.key) { a in
                    ZStack(alignment: .topTrailing) {
                        Image(platform: a.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 58, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .opacity(a.uploadId == nil ? 0.45 : 1)
                        Button {
                            attachments.removeAll { $0.key == a.key }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 5, y: -5)
                    }
                }
            }
            .padding(.top, 6)
        }
    }


    func attach(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard attachments.count < 4, let api = model.api else { break }
            guard let data = try? await item.loadTransferable(type: Data.self), let image = PlatformImage(data: data),
                  let jpeg = image.scaledJPEG()
            else {
                error = "Could not read that image"
                continue
            }
            let a = Attachment(image: image)
            attachments.append(a)
            do {
                let id = try await api.upload(jpeg, type: "image/jpeg")
                if let i = attachments.firstIndex(where: { $0.key == a.key }) { attachments[i].uploadId = id }
            } catch {
                attachments.removeAll { $0.key == a.key }
                self.error = error.localizedDescription
            }
        }
    }

    func send(_ c: ComposerState) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard c.enabled, !sending, !text.isEmpty || !attachments.isEmpty, let api = model.api else { return }
        if attachments.contains(where: { $0.uploadId == nil }) {
            error = "Wait for the images to upload"
            return
        }
        if c.decline && !attachments.isEmpty {
            error = "Answer the request first, then send images"
            return
        }
        let images = attachments.compactMap(\.uploadId)
        let kept = (draft, attachments)
        sending = true
        error = nil
        draft = ""
        attachments = []
        defer { sending = false }
        do {
            if let a = agent {
                if c.decline {
                    try await api.agent(["action": "respond", "id": a.id, "answer": ["allow": false, "message": text]])
                } else {
                    try await api.agent(["action": "send", "id": a.id, "prompt": text, "images": images])
                }
            } else if let s = session {
                if c.live {
                    try await api.agent(["action": "live-send", "profile": s.profile, "sid": s.id, "prompt": text, "images": images])
                    withAnimation { toast = "Sent to its terminal" }
                } else {
                    let data = try await api.agentData(
                        ["action": "create", "profile": s.profile, "cwd": s.cwd, "sid": s.id, "prompt": text, "images": images])
                    let reply = try JSONDecoder().decode(JSON.self, from: data)
                    if reply["queued"]?.bool == true {
                        withAnimation { toast = reply["busy"]?.bool == true ? "Queued after the current reply" : "Sent to Codex" }
                    } else {
                        let created = try JSONDecoder().decode(Agent.self, from: data)
                        if !model.agents.contains(where: { $0.id == created.id }) { model.agents.insert(created, at: 0) }
                        current = .agent(created.id)
                    }
                }
            }
        } catch {
            (draft, attachments) = kept
            self.error = error.localizedDescription
        }
    }

    func takeOver() async {
        guard let s = session else { return }
        do {
            try await model.api?.agent(["action": "takeover", "profile": s.profile, "sid": s.id])
            withAnimation { toast = "Stopped in the terminal. Continue here." }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
#endif
