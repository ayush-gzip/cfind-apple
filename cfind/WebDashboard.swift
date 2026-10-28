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

    let view: DashboardWebView
    /// The daemon did not answer; the window says so and tries again.
    private(set) var down = false
    @ObservationIgnored weak var model: AppModel?
    @ObservationIgnored private var origin: URL?
    /// A chat asked for before the page finished loading.
    @ObservationIgnored private var pending: ChatTarget?
    @ObservationIgnored private var retry: Task<Void, Never>?
    /// The page's own light or dark choice. The glass must match it, or the
    /// sidebar text is hard to read.
    @ObservationIgnored private var appearance: NSAppearance?
    /// The script that last gave the page its window layout values.
    @ObservationIgnored private var chrome = ""
    /// The page's top row in points. The window buttons sit in its middle.
    private static let bar = 52.0

    override private init() {
        let config = WKWebViewConfiguration()
        view = DashboardWebView(frame: .zero, configuration: config)
        super.init()
        // The page posts the chat on screen here (dashboard.js `tellApp`).
        config.userContentController.add(self, name: "cfind")
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = false
        // The glass behind the window shows where the page is transparent.
        view.setValue(false, forKey: "drawsBackground")
        view.underPageBackgroundColor = .clear
        let saved = UserDefaults.standard.double(forKey: "zoom")
        if saved > 0 { view.pageZoom = saved }
        view.attached = { [weak self] window in
            // The scene hides the title bar; the window is clear so the glass shows.
            window.isOpaque = false
            window.backgroundColor = .clear
            window.appearance = self?.appearance
            self?.layoutChrome()
        }
        // AppKit puts the window buttons back in place on resize and full screen.
        for name in [NSWindow.didResizeNotification, NSWindow.didEnterFullScreenNotification,
                     NSWindow.didExitFullScreenNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    if note.object as? NSWindow === self?.view.window { self?.layoutChrome() }
                }
            }
        }
        layoutChrome()
    }

    /// ⌘+ and ⌘- step the page zoom, ⌘0 resets it. Kept across launches.
    func zoom(by step: Double?) {
        view.pageZoom = step.map { min(3, max(0.5, view.pageZoom + $0)) } ?? 1
        UserDefaults.standard.set(Double(view.pageZoom), forKey: "zoom")
        layoutChrome()
    }

    /// Moves the window buttons into the middle of the page's top row, as in apps
    /// with a sidebar, and tells the page: `mac-app` on <html>, `--mac-lights` (left
    /// inset past the buttons) and `--mac-bar` (row height) in CSS px. The same
    /// script runs at document start, so a reload has them from the first paint.
    private func layoutChrome() {
        let bar = Self.bar
        var lights = 0.0
        // In full screen the buttons live in the menu bar's drop-down; leave them there.
        if let window = view.window, !window.styleMask.contains(.fullScreen),
           let close = window.standardWindowButton(.closeButton),
           let mini = window.standardWindowButton(.miniaturizeButton),
           let zoom = window.standardWindowButton(.zoomButton),
           let titlebar = close.superview?.superview {
            titlebar.frame = NSRect(x: 0, y: window.frame.height - bar, width: titlebar.frame.width, height: bar)
            let space = mini.frame.minX - close.frame.minX
            for (i, button) in [close, mini, zoom].enumerated() {
                button.setFrameOrigin(NSPoint(x: bar / 2 - button.frame.width / 2 + Double(i) * space,
                                              y: (bar - button.frame.height) / 2))
            }
            lights = zoom.convert(zoom.bounds, to: nil).maxX + 12
        }
        let zoom = view.pageZoom
        let js = """
            document.documentElement.classList.add('mac-app');
            document.documentElement.style.setProperty('--mac-lights', '\(lights / zoom)px');
            document.documentElement.style.setProperty('--mac-bar', '\(bar / zoom)px');
            """
        // A live resize calls this on every frame.
        guard js != chrome else { return }
        chrome = js
        let scripts = view.configuration.userContentController
        scripts.removeAllUserScripts()
        scripts.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        view.evaluateJavaScript(js)
    }

    /// A double-click on the page's top row does what a title bar double-click does
    /// (System Settings, Desktop & Dock).
    private func zoomWindow() {
        guard let window = view.window else { return }
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window.miniaturize(nil)
        case "None", "Do Nothing": break
        default: window.performZoom(nil)
        }
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
        if key == "window:drag" { return view.dragWindow() }
        if key == "window:zoom" { return zoomWindow() }
        if key == "window:fullscreen" { return view.window?.toggleFullScreen(nil) ?? () }
        if key == "theme:dark" || key == "theme:light" {
            appearance = NSAppearance(named: key == "theme:dark" ? .darkAqua : .aqua)
            view.window?.appearance = appearance
            return
        }
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
            .ignoresSafeArea()
            .background { Glass().ignoresSafeArea() }
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

private struct Glass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// The window has no title bar to drag, so the page asks for a drag from its top
/// row while the mouse is still down.
final class DashboardWebView: WKWebView {
    var attached: ((NSWindow) -> Void)?
    private var lastMouseDown: NSEvent?

    override func mouseDown(with event: NSEvent) {
        lastMouseDown = event
        super.mouseDown(with: event)
    }

    /// The mouse's side buttons go back and forward, as in a browser. The page
    /// keeps a history step for each section and each chat.
    override func otherMouseDown(with event: NSEvent) {
        if ![3, 4].contains(event.buttonNumber) { super.otherMouseDown(with: event) }
    }

    override func otherMouseUp(with event: NSEvent) {
        switch event.buttonNumber {
        case 3: evaluateJavaScript("history.back()")
        case 4: evaluateJavaScript("history.forward()")
        default: super.otherMouseUp(with: event)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { attached?(window) }
    }

    func dragWindow() {
        guard let down = lastMouseDown, let window else { return }
        window.performDrag(with: down)
        // The drag can end without the page seeing the mouse-up. Without one it
        // stays pressed and misses the double-click.
        if let up = NSEvent.mouseEvent(with: .leftMouseUp, location: down.locationInWindow,
                                       modifierFlags: down.modifierFlags,
                                       timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: down.windowNumber, context: nil,
                                       eventNumber: down.eventNumber, clickCount: down.clickCount,
                                       pressure: 0) {
            super.mouseUp(with: up)
        }
    }
}
#endif
