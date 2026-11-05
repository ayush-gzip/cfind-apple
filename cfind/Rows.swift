#if os(iOS)
import SwiftUI

extension AppModel {
    /// "Claude · Personal" shows as "Personal".
    func shortLabel(_ profile: String) -> String {
        label(profile).split(separator: "·").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? profile
    }

    /// Subagents of a session, as on the website: all of them while the parent works,
    /// only the live ones once it is idle. Newest first, five at most.
    func subagents(of parent: String?, profile: String, parentState: String) -> (shown: [Session], more: Int) {
        guard let parent else { return ([], 0) }
        let all = (snapshot?.sessions ?? []).filter {
            $0.parent == parent && $0.profile == profile
                && (parentState != "idle" || ["running", "waiting"].contains($0.state))
        }.sorted { $0.updatedAt > $1.updatedAt }
        return (Array(all.prefix(5)), max(0, all.count - 5))
    }
}

/// The agent's mark and the profile name, in the profile's colour.
struct ProfileTag: View {
    let profile: String
    @Environment(AppModel.self) private var model
    /// Increased on a selected row, where the profile colour is hard to read.
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        HStack(spacing: 4) {
            Image(model.profile(profile)?.source == "codex" ? "CodexMark" : "ClaudeMark")
                .resizable()
                .scaledToFit()
                .frame(width: 12, height: 12)
            Text(model.shortLabel(profile))
        }
        .foregroundStyle(prominence == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(profileColor(profile)))
        .accessibilityElement(children: .combine)
    }
}

/// The agent's mark in a circle of the profile colour, with a dot for a state that needs a look.
struct Avatar: View {
    let profile: String
    let state: String
    @Environment(AppModel.self) private var model

    var body: some View {
        Image(model.profile(profile)?.source == "codex" ? "CodexMark" : "ClaudeMark")
            .resizable()
            .scaledToFit()
            .frame(width: 20, height: 20)
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(profileColor(profile).gradient, in: Circle())
            .overlay(alignment: .bottomTrailing) {
                if notable(state) {
                    Circle()
                        .fill(StateDot(state: state).color)
                        .padding(2.5)
                        .background(Color(.secondarySystemGroupedBackground), in: Circle())
                        .frame(width: 15, height: 15)
                        .offset(x: 2, y: 2)
                }
            }
            .accessibilityHidden(true)
    }
}

/// States worth a coloured word in a row; idle and finished ones are not.
func notable(_ state: String) -> Bool {
    ["running", "queued", "waiting", "asking", "failed", "errored", "stale"].contains(state)
}

/// A session or agent in a list, as a Messages conversation: the folder as the
/// name, the task (or the question it asks) as the preview.
struct RowLabel: View {
    let title: String
    let state: String
    let profile: String
    let cwd: String
    let updatedAt: Double
    var ask: String?
    var terminal = false
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        // At the largest text sizes the profile shows only as the avatar's colour.
        let big = size.isAccessibilitySize
        HStack(alignment: .top, spacing: 12) {
            Avatar(profile: profile, state: state)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(URL(fileURLWithPath: cwd).lastPathComponent)
                        .font(.body.weight(.semibold))
                        .lineLimit(big ? 2 : 1)
                        .layoutPriority(1)
                    if !big {
                        Text(model.shortLabel(profile))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if terminal {
                        Image(systemName: "terminal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("In a terminal")
                    }
                    Spacer(minLength: 4)
                    Text(age(updatedAt))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                preview
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(big ? 6 : 2)
            }
        }
        .padding(.vertical, 4)
    }

    var preview: Text {
        let text = Text(oneLine(state == "asking" ? ask ?? title : title))
        guard notable(state) else { return text }
        // Yellow words are hard to read on white.
        let word = Text(stateLabel(state)).fontWeight(.medium)
            .foregroundStyle(state == "stale" ? Color.secondary : StateDot(state: state).color)
        return Text("\(word) · \(text)")
    }
}

/// The subagents of a session or agent, folded under it.
struct SubagentRows: View {
    let parent: String?
    let profile: String
    let state: String
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        let found = model.subagents(of: parent, profile: profile, parentState: state)
        if !found.shown.isEmpty {
            DisclosureGroup(isExpanded: $open) {
                ForEach(found.shown, id: \.path) { s in
                    ChatLink(target: .session(s.path)) {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 1).fill(profileColor(profile)).frame(width: 2)
                            Text(oneLine(s.title)).lineLimit(1)
                            Spacer(minLength: 4)
                            StateDot(state: s.state)
                        }
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if found.more > 0 {
                    Text("+\(found.more) more").font(.caption).foregroundStyle(.secondary)
                }
            } label: {
                Text(summary(found))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 14)
            }
        }
    }

    func summary(_ found: (shown: [Session], more: Int)) -> String {
        let count = found.shown.count + found.more
        let live = found.shown.filter { ["running", "waiting"].contains($0.state) }.count
        return "↳ \(count) subagent\(count == 1 ? "" : "s")" + (live > 0 ? " · \(live) running" : "")
    }
}
#endif
