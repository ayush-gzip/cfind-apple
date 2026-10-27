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

/// A session or agent in a list: title, then state, profile and folder.
struct RowLabel: View {
    let title: String
    let state: String
    let profile: String
    let cwd: String
    let updatedAt: Double
    var terminal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(oneLine(title)).font(.body).lineLimit(2)
            HStack(spacing: 6) {
                StateDot(state: state)
                if terminal { Image(systemName: "terminal").accessibilityLabel("In a terminal") }
                Text(stateLabel(state))
                ProfileTag(profile: profile)
                Text("· \(folder(cwd))").lineLimit(1)
                Spacer(minLength: 4)
                Text(age(updatedAt))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
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
