#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// The Mac window shows the dashboard website from the daemon. The app adds the
/// Dock icon, notifications and ⌘N. One web view lives for the whole app, so
/// closing and opening the window keeps the page.
@Observable @MainActor
final class WebDashboard: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    static let shared = WebDashboard()

    let view: WKWebView
    /// The daemon did not answer; the window says so and tries again.
    private(set) var down = false
    @ObservationIgnored weak var model: AppModel?
    @ObservationIgnored private var origin: URL?
    /// A chat asked for before the page finished loading.
    @ObservationIgnored private var pending: ChatTarget?
    @ObservationIgnored private var retry: Task<Void, Never>?

    override private init() {
        let config = WKWebViewConfiguration()
        view = WKWebView(frame: .zero, configuration: config)
        super.init()
        // The page posts the chat on screen here (dashboard.js `tellApp`).
        config.userContentController.add(self, name: "cfind")
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = false
        let saved = UserDefaults.standard.double(forKey: "zoom")
        if saved > 0 { view.pageZoom = saved }
    }

    /// ⌘+ and ⌘- step the page zoom, ⌘0 resets it. Kept across launches.
    func zoom(by step: Double?) {
        view.pageZoom = step.map { min(3, max(0.5, view.pageZoom + $0)) } ?? 1
        UserDefaults.standard.set(Double(view.pageZoom), forKey: "zoom")
    }

    func load() {
        retry?.cancel()
        // The daemon may have restarted with a new port.
        guard let service = ServiceFile.load(),
              var url = URLComponents(url: service.base, resolvingAgainstBaseURL: false)
        else { return failed() }
        url.queryItems = [URLQueryItem(name: "t", value: service.token)]
        origin = service.base
        view.load(URLRequest(url: url.url!))
    }

    func show(_ target: ChatTarget) {
        guard !view.isLoading, !down else { pending = target; return }
        let (kind, id) = switch target {
        case .agent(let id): ("agent", id)
        case .session(let path): ("session", path)
        }
        view.callAsyncJavaScript("window.cfindOpen?.(kind, id)", arguments: ["kind": kind, "id": id],
                                 in: nil, in: .page)
    }

    func newAgent() {
        view.evaluateJavaScript("document.getElementById('new-agent')?.click()")
    }

    private func failed() {
        down = true
        retry = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { load() }
        }
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        down = false
        if let t = pending {
            pending = nil
            show(t)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { failed() }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        load()
    }

    /// Only the dashboard loads in the window. Other links open in the browser.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        if url.scheme == "about" || url.scheme == "blob" { return .allow }
        if url.scheme == origin?.scheme && url.host() == origin?.host() && url.port == origin?.port { return .allow }
        if ["http", "https", "mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
        return .cancel
    }

    /// `target="_blank"` links, such as sign-in pages.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, ["http", "https"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
        return nil
    }

    /// The composer's attach button.
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.allowedContentTypes = [.image]
        return await panel.begin() == .OK ? panel.urls : nil
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let key = message.body as? String ?? ""
        if key.hasPrefix("agent:") {
            model?.onScreen = .agent(String(key.dropFirst(6)))
        } else if key.hasPrefix("session:") {
            model?.onScreen = .session(String(key.dropFirst(8)))
        } else {
            model?.onScreen = nil
        }
    }
}

struct WebRoot: View {
    @Environment(AppModel.self) private var model
    private let web = WebDashboard.shared

    var body: some View {
        WebView(view: web.view)
            .overlay {
                if web.down {
                    ContentUnavailableView {
                        Label("cfind is not running", systemImage: "bolt.horizontal.circle")
                    } description: {
                        Text("Start it with `cfind daemon start`. This window tries again every few seconds.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
                }
            }
            .frame(minWidth: 900, minHeight: 600)
            .onAppear {
                web.model = model
                if web.view.url == nil { web.load() }
            }
            .onChange(of: model.open, initial: true) { _, target in
                guard let target else { return }
                model.open = nil
                web.show(target)
                NSApp.activate()
            }
    }
}

private struct WebView: NSViewRepresentable {
    let view: WKWebView
    func makeNSView(context: Context) -> WKWebView { view }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
#endif
