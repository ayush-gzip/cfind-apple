#if os(macOS)
import AppKit
import UserNotifications

/// Posts a banner when an agent or terminal session needs you or finishes.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private var last: NotifyState?
    private weak var model: AppModel?
    private var viewing: ChatTarget?

    func start(model: AppModel) {
        self.model = model
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Call after every change to agents or sessions, and when the chat on screen changes.
    func update(model: AppModel, viewing: ChatTarget?) {
        self.viewing = viewing
        let sessions = (model.snapshot?.sessions ?? []).filter {
            $0.parent == nil && $0.open == true && model.agent(for: $0) == nil
        }
        // Until the first snapshot arrives there is nothing to compare against.
        guard model.snapshot != nil else { return }
        let new = NotifyState(agents: model.agents, sessions: sessions)
        let found = notes(old: last, new: new, viewing: viewing.map(NotifyTarget.init), agentName: model.agentName)
        last = new
        for n in found {
            let content = UNMutableNotificationContent()
            content.title = n.title
            content.body = n.body
            content.sound = .default
            switch n.target {
            case .agent(let id):
                content.threadIdentifier = "agent:\(id)"
                content.userInfo = ["kind": "agent", "id": id]
            case .session(let path):
                content.threadIdentifier = "session:\(path)"
                content.userInfo = ["kind": "session", "id": path]
            }
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: n.id, content: content, trigger: nil))
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let t = Self.target(notification.request.content.userInfo)
        return await MainActor.run { t == viewing ? [] : [.banner, .sound] }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let t = Self.target(response.notification.request.content.userInfo) else { return }
        await MainActor.run {
            model?.open = t
            NSApp.activate()
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }
    }

    private nonisolated static func target(_ info: [AnyHashable: Any]) -> ChatTarget? {
        guard let id = info["id"] as? String else { return nil }
        switch info["kind"] as? String {
        case "agent": return .agent(id)
        case "session": return .session(id)
        default: return nil
        }
    }
}

private extension NotifyTarget {
    init(_ t: ChatTarget) {
        switch t {
        case .agent(let id): self = .agent(id)
        case .session(let p): self = .session(p)
        }
    }
}
#endif
