#if os(iOS)
import SwiftUI
import UIKit

typealias PlatformImage = UIImage

extension Image {
    init(platform image: PlatformImage) {
        self.init(uiImage: image)
    }
}

extension PlatformImage {
    /// Photos are often HEIC and large; the Mac takes JPEG up to 10 MB.
    func scaledJPEG(maxSide: CGFloat = 2048) -> Data? {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format)
            .image { _ in draw(in: CGRect(origin: .zero, size: target)) }
            .jpegData(compressionQuality: 0.85)
    }
}

enum Pasteboard {
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}

/// The system colours the chat uses.
extension Color {
    static let surface = Color(.secondarySystemBackground)
    static let surfaceRaised = Color(.tertiarySystemBackground)
    static let line = Color(.separator)
    static let dim = Color(.tertiaryLabel)
    static let dimFill = Color(.tertiarySystemFill)
}

extension View {
    func inlineTitle() -> some View {
        navigationBarTitleDisplayMode(.inline)
    }

    func noAutocapitalization() -> some View {
        textInputAutocapitalization(.never)
    }
}

extension SearchFieldPlacement {
    static var sessions: SearchFieldPlacement { .navigationBarDrawer(displayMode: .always) }
}

/// Each tab pushes chats inside its own stack.
struct TabStack<Content: View>: View {
    var path: Binding<[ChatTarget]>?
    @ViewBuilder var content: Content

    var body: some View {
        if let path {
            NavigationStack(path: path) { content.navigationDestination(for: ChatTarget.self) { ChatView(target: $0) } }
        } else {
            NavigationStack { content.navigationDestination(for: ChatTarget.self) { ChatView(target: $0) } }
        }
    }
}

/// A list row that opens a chat.
struct ChatLink<Content: View>: View {
    let target: ChatTarget
    @ViewBuilder var content: Content

    var body: some View {
        NavigationLink(value: target) { content }
    }
}

struct ChatList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        List { content }
    }
}
#endif
