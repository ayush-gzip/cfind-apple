import Observation
import SwiftUI

/// Live state from the Mac: sessions and limits (`metrics`) and dashboard agents
/// (`workspace`), both pushed over one event stream.
@Observable @MainActor
final class AppModel {
    #if os(iOS)
    var pairing: Pairing? = Keychain.load()
    /// The Mac refused the token: it was revoked there.
    var revoked = false
    /// A pairing link opened from outside; shown for confirmation before use.
    var link: PairLink?
    static let pairs = true
    static let unreachable = "Your Mac is not reachable"
    #else
    /// Read from the daemon's service file; there is no pairing on the Mac.
    var pairing: Pairing? = ServiceFile.load()
    let revoked = false
    static let pairs = false
    static let unreachable = "cfind daemon is not running. Run `cfind daemon start`."
    #endif
    /// A chat to show, set from outside (a notification click). The Mac window selects it and comes forward.
    var open: ChatTarget?
    #if os(macOS)
    /// The chat in the window; no notification for it while the app is in front.
    var onScreen: ChatTarget?
    #endif
    var snapshot: Snapshot?
    var agents: [Agent] = []
    var connected = false
    var problem: String?
    private var stream: Task<Void, Never>?

    var api: API? { pairing.map(API.init) }

    func connect() {
        #if os(iOS)
        guard api != nil else { return }
        #endif
        guard stream == nil, !revoked else { return }
        stream = Task {
            var delay = 1.0
            while !Task.isCancelled {
                #if os(macOS)
                // The daemon may have restarted with a new port or token.
                pairing = ServiceFile.load()
                #endif
                do {
                    guard let api else { throw URLError(.cannotConnectToHost) }
                    for try await event in api.events() {
                        connected = true
                        problem = nil
                        delay = 1
                        switch event {
                        case .metrics(let s): snapshot = s
                        case .workspace(let a): agents = a
                        }
                        #if os(macOS)
                        Notifier.shared.update(model: self, viewing: NSApp.isActive ? onScreen : nil)
                        #endif
                    }
                } catch APIError.unpaired where Self.pairs {
                    #if os(iOS)
                    revoked = true
                    #endif
                    connected = false
                    stream = nil
                    return
                } catch {
                    if !Task.isCancelled { problem = Self.unreachable }
                }
                connected = false
                try? await Task.sleep(for: .seconds(delay))
                delay = min(delay * 2, 15)
            }
        }
    }

    func disconnect() {
        stream?.cancel()
        stream = nil
        connected = false
    }

    #if os(iOS)
    func paired(_ pairing: Pairing) {
        Keychain.save(pairing)
        disconnect()
        self.pairing = pairing
        revoked = false
        link = nil
        connect()
    }

    func unpair() async {
        try? await api?.unpair()
        Keychain.delete()
        disconnect()
        pairing = nil
        snapshot = nil
        agents = []
    }
    #endif

    func profile(_ id: String) -> Profile? { snapshot?.profiles.first { $0.id == id } }
    func label(_ profile: String) -> String { self.profile(profile)?.label ?? profile }
    func agentName(_ profile: String) -> String { self.profile(profile)?.source == "codex" ? "Codex" : "Claude" }
    /// A session the dashboard continued opens as that agent.
    func agent(for s: Session) -> Agent? {
        agents.first { $0.profile == s.profile && ($0.history == s.path || $0.sid == s.id) }
    }
}
