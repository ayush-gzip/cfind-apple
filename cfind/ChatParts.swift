#if os(iOS)
import SwiftUI

struct Bubble: View {
    let message: Message
    let user: Bool
    let label: String
    var queued = false

    var body: some View {
        VStack(alignment: user ? .trailing : .leading, spacing: 4) {
            if let images = message.images, !images.isEmpty {
                HStack(spacing: 6) {
                    ForEach(images.indices, id: \.self) { RemoteImage(source: images[$0]) }
                }
                .opacity(queued ? 0.6 : 1)
            }
            if !message.text.isEmpty {
                MarkdownText(text: message.text)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(background, in: shape)
                    .overlay {
                        if queued { shape.strokeBorder(Color.line, style: StrokeStyle(lineWidth: 1, dash: [4])) }
                    }
                    .foregroundStyle(queued ? .secondary : .primary)
                    .contextMenu {
                        Button("Copy", systemImage: "doc.on.doc") { Pasteboard.copy(message.text) }
                    }
            }
            if !queued {
                HStack(spacing: 6) {
                    Text(user ? "You" : label)
                    if let t = message.time { Text(Date(timeIntervalSince1970: t / 1000), style: .time) }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            } else {
                Text("Queued").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: user ? .trailing : .leading)
        .padding(user ? .leading : .trailing, Self.gutter)
    }

    static let gutter = 36.0
    var background: Color { queued ? .clear : user ? Color.blue.opacity(0.16) : Color.surface }

    var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii: .init(
            topLeading: user ? 18 : 6, bottomLeading: 18, bottomTrailing: 18, topTrailing: user ? 6 : 18))
    }
}

struct NoteRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }
}

struct TypingBubble: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .frame(width: 7, height: 7)
                    .opacity(phase ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2), value: phase)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.surface, in: Capsule())
        .onAppear { phase = true }
        .accessibilityLabel("Working")
    }
}

struct ToolRow: View {
    let message: Message
    var opened: () -> Void
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { open.toggle() }
                if open { opened() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "terminal").font(.caption).foregroundStyle(.secondary)
                    Text(message.tool?.name ?? "Tool").font(.footnote.weight(.semibold))
                    Text(message.text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let tool = message.tool, tool.output != nil {
                        Text(tool.error == true ? "Failed" : "Done")
                            .font(.caption2)
                            .foregroundStyle(tool.error == true ? .red : .secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open, let tool = message.tool {
                CodeBlock(label: "Input", text: tool.input)
                if let output = tool.output {
                    CodeBlock(label: tool.error == true ? "Error" : "Output", text: output.isEmpty ? "(no output)" : output)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.line))
        .padding(.trailing, 20)
    }
}

struct CodeBlock: View {
    let label: String
    let text: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button {
                    Pasteboard.copy(text)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.caption)
                }
                .accessibilityLabel("Copy")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
        }
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.line.opacity(0.6)))
    }
}

/// Markdown in chat: fenced code becomes a code block; headings, lists and
/// inline styles render natively. Transcript HTML is never rendered.
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Markdown.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .code(let lang, let code):
                    CodeBlock(label: lang.isEmpty ? "Code" : lang, text: code)
                case .heading(let line):
                    Text(Markdown.inline(line)).font(.headline)
                case .text(let para):
                    Text(Markdown.inline(para))
                }
            }
        }
    }
}

enum Markdown {
    enum Block {
        case text(String)
        case heading(String)
        case code(String, String)
    }

    static func blocks(_ text: String) -> [Block] {
        var out: [Block] = [], para: [String] = [], code: [String]?, lang = ""
        func flush() {
            if !para.isEmpty { out.append(.text(para.joined(separator: "\n"))) }
            para = []
        }
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let c = code {
                    out.append(.code(lang, c.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = []
                    lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
            } else if code != nil {
                code?.append(line)
            } else if let r = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                flush()
                out.append(.heading(String(line[r.upperBound...])))
            } else if trimmed.isEmpty {
                flush()
            } else {
                para.append(line)
            }
        }
        if let c = code { out.append(.code(lang, c.joined(separator: "\n"))) }
        flush()
        return out
    }

    /// Inline Markdown per paragraph; list markers become bullets.
    static func inline(_ text: String) -> AttributedString {
        let lines = text.components(separatedBy: "\n").map { line -> String in
            guard let r = line.range(of: #"^\s*[-*+]\s+"#, options: .regularExpression) else { return line }
            return String(line.prefix { $0 == " " }) + "• " + line[r.upperBound...]
        }
        let joined = lines.joined(separator: "\n")
        return (try? AttributedString(
            markdown: joined, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(joined)
    }
}

@MainActor
enum ImageCache {
    static let cache = NSCache<NSString, PlatformImage>()
    static let uploadId = #/^[0-9a-f]{32}\.(png|jpg|gif|webp)$/#

    static func load(_ source: String, api: API?) async -> PlatformImage? {
        if let hit = cache.object(forKey: source as NSString) { return hit }
        var image: PlatformImage?
        if source.hasPrefix("data:image/"), let comma = source.firstIndex(of: ","),
           let data = Data(base64Encoded: String(source[source.index(after: comma)...])) {
            image = PlatformImage(data: data)
        } else if source.wholeMatch(of: uploadId) != nil, let api, let data = try? await api.image(source) {
            image = PlatformImage(data: data)
        }
        if let image { cache.setObject(image, forKey: source as NSString) }
        return image
    }
}

struct RemoteImage: View {
    let source: String
    @Environment(AppModel.self) private var model
    @State private var image: PlatformImage?
    @State private var viewing = false

    var body: some View {
        Group {
            if let image {
                Image(platform: image).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 14).fill(Color.dimFill).frame(width: 110, height: 110)
            }
        }
        .frame(maxWidth: 220, maxHeight: 220)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { if image != nil { viewing = true } }
        .task(id: source) { image = await ImageCache.load(source, api: model.api) }
        .fullScreenCover(isPresented: $viewing) { viewer }
        .accessibilityLabel("Attached image")
    }

    var viewer: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image { Image(platform: image).resizable().scaledToFit() }
        }
        .onTapGesture { viewing = false }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Close image")
    }
}

/// An approval or a question from a dashboard agent.
struct PendingCard: View {
    let agent: Agent
    @Environment(AppModel.self) private var model
    @State private var picked: [String: [String]] = [:]
    @State private var other: [String: String] = [:]
    @State private var busy = false
    @State private var error: String?

    struct Question {
        var key: String
        var header: String
        var question: String
        var options: [(label: String, detail: String)]
        var multi: Bool
        var other: Bool
        var secret: Bool
    }

    var params: JSON { agent.pending?.params ?? .null }

    var questions: [Question]? {
        guard let p = agent.pending else { return nil }
        func options(_ j: JSON?) -> [(label: String, detail: String)] {
            (j?.array ?? []).map { ($0["label"]?.string ?? "", $0["description"]?.string ?? "") }
        }
        if p.method == "item/tool/requestUserInput" {
            return (params["questions"]?.array ?? []).map { q in
                Question(key: q["id"]?.string ?? "", header: q["header"]?.string ?? "",
                         question: q["question"]?.string ?? "", options: options(q["options"]), multi: false,
                         other: q["isOther"]?.bool == true || (q["options"]?.array ?? []).isEmpty,
                         secret: q["isSecret"]?.bool == true)
            }
        }
        if params["tool_name"]?.string == "AskUserQuestion" {
            return (params["input"]?["questions"]?.array ?? []).map { q in
                Question(key: q["question"]?.string ?? "", header: q["header"]?.string ?? "",
                         question: q["question"]?.string ?? "", options: options(q["options"]),
                         multi: q["multiSelect"]?.bool == true, other: true, secret: false)
            }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let qs = questions {
                Label("\(model.agentName(agent.profile)) is asking", systemImage: "questionmark.circle")
                    .font(.subheadline.weight(.semibold))
                ForEach(qs.indices, id: \.self) { questionView(qs[$0], single: qs.count == 1) }
                HStack {
                    Button("Skip") { Task { await respond(["allow": false]) } }.buttonStyle(.bordered)
                    Spacer()
                    Button("Send answer") {
                        if let a = answers(qs) { Task { await respond(["allow": true, "answers": a]) } }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(answers(qs) == nil)
                }
            } else {
                permissionView
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(14)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 16))
        .disabled(busy)
    }

    @ViewBuilder var permissionView: some View {
        let p = agent.pending
        let claude = p?.method == "can_use_tool"
        let input = params["input"] ?? .null
        let tool = params["display_name"]?.string ?? params["tool_name"]?.string ?? "this tool"
        let preview = previewOf(claude: claude, input: input)
        let suggestions = params["permission_suggestions"]?.array ?? []
        let always: String? = claude
            ? (suggestions.contains { $0["destination"]?.string == "session" }
                ? (suggestions.contains { $0["mode"]?.string == "acceptEdits" } ? "Allow edits this session" : "Allow this session")
                : nil)
            : (["item/commandExecution/requestApproval", "item/fileChange/requestApproval"].contains(p?.method ?? "")
                ? "Allow this session" : nil)
        let title = claude ? "Allow \(tool)?"
            : p?.method == "item/fileChange/requestApproval" ? "Allow these file changes?"
            : p?.method == "item/commandExecution/requestApproval" ? "Allow this command?"
            : p?.method == "mcpServer/elicitation/request" ? (params["message"]?.string ?? "A tool needs your input")
            : "Allow this request?"
        Label(title, systemImage: "checkmark.shield").font(.subheadline.weight(.semibold))
        if let reason = params["description"]?.string ?? params["reason"]?.string {
            Text(reason).font(.footnote).foregroundStyle(.secondary)
        }
        CodeBlock(label: preview.label, text: preview.text)
        HStack {
            Button("Decline") { Task { await respond(["allow": false, "always": false]) } }.buttonStyle(.bordered)
            Spacer()
            Button("Allow once") { Task { await respond(["allow": true, "always": false]) } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        if let always {
            Button(always) { Task { await respond(["allow": true, "always": true]) } }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
        }
        if claude {
            Text("Or write a reply below to decline and tell \(model.agentName(agent.profile)) what to do instead.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    func previewOf(claude: Bool, input: JSON) -> (label: String, text: String) {
        if claude {
            if let command = input["command"]?.string { return ("Command", command) }
            if let file = input["file_path"]?.string {
                let diff = [input["old_string"]?.string.map { "- " + $0 }, input["new_string"]?.string.map { "+ " + $0 }]
                return (file, input["content"]?.string ?? diff.compactMap { $0 }.joined(separator: "\n"))
            }
            return ("Input", input.pretty)
        }
        if let command = params["command"]?.string {
            return (params["cwd"]?.string.map { "Command · " + folder($0) } ?? "Command", command)
        }
        if let id = params["itemId"]?.string, let change = agent.messages.first(where: { $0.id == id })?.tool {
            return ("Changes", change.input)
        }
        return ("Request", (params["permissions"] ?? params["requestedSchema"] ?? params).pretty)
    }

    func questionView(_ q: Question, single: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !q.header.isEmpty { Text(q.header).font(.caption).foregroundStyle(.secondary) }
            Text(q.question).font(.callout)
            ForEach(q.options.indices, id: \.self) { i in
                let option = q.options[i]
                let on = picked[q.key]?.contains(option.label) == true
                Button {
                    var list = q.multi ? (picked[q.key] ?? []) : []
                    if on { list.removeAll { $0 == option.label } } else { list.append(option.label) }
                    picked[q.key] = list
                    // One single-choice question works like a quick reply.
                    if single && !q.multi && !on && (other[q.key] ?? "").isEmpty, let a = answers([q]) {
                        Task { await respond(["allow": true, "answers": a]) }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.label).font(.callout.weight(.medium))
                        if !option.detail.isEmpty && option.detail != option.label {
                            Text(option.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(on ? Color.accentColor.opacity(0.15) : Color.surfaceRaised,
                                in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? Color.accentColor : .clear))
                }
                .buttonStyle(.plain)
            }
            if q.other {
                let field = Binding(get: { other[q.key] ?? "" }, set: { other[q.key] = $0 })
                let prompt = q.options.isEmpty ? "Type your answer" : "Or type your own answer"
                Group {
                    if q.secret { SecureField(prompt, text: field) } else { TextField(prompt, text: field) }
                }
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    func answers(_ qs: [Question]) -> [String: [String]]? {
        var out: [String: [String]] = [:]
        for q in qs {
            var list = picked[q.key] ?? []
            let typed = (other[q.key] ?? "").trimmingCharacters(in: .whitespaces)
            if !typed.isEmpty { list.append(typed) }
            if list.isEmpty { return nil }
            out[q.key] = list
        }
        return out
    }

    func respond(_ answer: [String: Any]) async {
        busy = true
        defer { busy = false }
        do {
            try await model.api?.agent(["action": "respond", "id": agent.id, "answer": answer])
        } catch {
            self.error = error.localizedDescription
        }
    }
}
#endif
