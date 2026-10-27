import SwiftUI

@main
struct CfindApp: App {
    @State private var model: AppModel
    #if os(iOS)
    @Environment(\.scenePhase) private var phase
    #endif

    init() {
        #if os(iOS)
        // UI tests start from an unpaired app.
        if ProcessInfo.processInfo.arguments.contains("-cfind-reset") { Keychain.delete() }
        #endif
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        #if os(iOS)
        WindowGroup {
            Group {
                if model.pairing == nil || model.revoked || model.link != nil {
                    PairView()
                } else {
                    RootView()
                }
            }
            .environment(model)
            .onOpenURL { url in model.link = PairLink(url) }
            .onChange(of: phase) { _, phase in
                // iOS stops the stream in the background; start it again on return.
                if phase == .active { model.connect() } else if phase == .background { model.disconnect() }
            }
            .task { model.connect() }
        }
        #else
        Window("cfind", id: "main") {
            WebRoot()
                .environment(model)
                .task {
                    Notifier.shared.start(model: model)
                    model.connect()
                }
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Agent") { WebDashboard.shared.newAgent() }.keyboardShortcut("n")
            }
        }
        #endif
    }
}

#if os(iOS)
struct RootView: View {
    var body: some View {
        TabView {
            SessionsView().tabItem { Label("Sessions", systemImage: "bubble.left.and.bubble.right") }
            AgentsView().tabItem { Label("Agents", systemImage: "terminal") }
            UsageView().tabItem { Label("Usage", systemImage: "gauge.with.dots.needle.33percent") }
            MacView().tabItem { Label("Mac", systemImage: "laptopcomputer") }
        }
    }
}

/// Shown at the top of lists while the stream is down.
struct ConnectionRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.connected {
            HStack(spacing: 10) {
                if model.problem == nil { ProgressView() } else {
                    Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.problem ?? (AppModel.pairs ? "Connecting to your Mac…" : "Connecting…")).font(.subheadline)
                    if model.problem != nil && AppModel.pairs {
                        Text("Check that the Mac is awake and Tailscale is on.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct StateDot: View {
    let state: String

    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
    }

    var color: Color {
        switch state {
        case "running", "queued": .blue
        case "waiting": .orange
        case "failed", "errored": .red
        case "stale": .yellow
        default: Color.dim
        }
    }
}
#endif
