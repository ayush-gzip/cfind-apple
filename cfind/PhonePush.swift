#if os(macOS)
import CoreGraphics
import CryptoKit
import SwiftUI

/// Sends notifications to the iPhone through Bark (github.com/Finb/Bark) while you are
/// away from the Mac. Bark's server sees only ciphertext: the text is sealed with AES-GCM
/// here and opened on the phone with the same key (Bark: Push Encryption, GCM, noPadding).
enum PhonePush {
    static let urlKey = "barkURL", keyKey = "barkKey", statusKey = "barkStatus"

    /// No keyboard or mouse input for 2 minutes, or the screen is locked.
    static var away: Bool {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return idle >= 120 || session?["CGSSessionScreenIsLocked"] as? Bool == true
    }

    static func send(_ n: Note) {
        let d = UserDefaults.standard
        guard let url = d.string(forKey: urlKey), !url.isEmpty, let key = d.string(forKey: keyKey) else { return }
        let target: ChatTarget = switch n.target {
        case .agent(let id): .agent(id)
        case .session(let path): .session(path)
        }
        Task { d.set(await post(title: n.title, body: n.body, link: target.link, url: url, key: key), forKey: statusKey) }
    }

    /// Sends one push and says how it went, for the Settings window.
    static func post(title: String, body: String, link: URL?, url: String, key: String) async -> String {
        do {
            let (data, response) = try await URLSession.shared.data(for: request(title: title, body: body, link: link, url: url, key: key))
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { return "Bark answered \(code): \(String(decoding: data.prefix(200), as: UTF8.self))" }
            return "Sent at \(Date.now.formatted(date: .omitted, time: .shortened))"
        } catch {
            return "Not sent: \(error.localizedDescription)"
        }
    }

    struct Problem: LocalizedError {
        let errorDescription: String?
    }

    /// The POST to the Bark URL: only `ciphertext` and a fresh `iv`, which Bark uses in place
    /// of the IV saved in the app. Bark decrypts with CryptoSwift's GCM, which wants the tag
    /// after the ciphertext.
    static func request(title: String, body: String, link: URL?, url: String, key: String,
                        iv: String = randomIV()) throws -> URLRequest {
        let base = url.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let endpoint = URL(string: base), ["http", "https"].contains(endpoint.scheme ?? "") else {
            throw Problem(errorDescription: "The Bark URL must look like https://api.day.app/YOUR_KEY")
        }
        // Bark reads the key as text and takes its bytes; 16, 24 or 32 picks AES-128, 192 or 256.
        guard key.allSatisfy(\.isASCII), [16, 24, 32].contains(key.count) else {
            throw Problem(errorDescription: "The encryption key must be 16, 24 or 32 plain characters")
        }
        var fields = ["title": title, "body": body, "group": "cfind"]
        fields["url"] = link?.absoluteString
        let box = try AES.GCM.seal(try JSONSerialization.data(withJSONObject: fields),
                                   using: SymmetricKey(data: Data(key.utf8)), nonce: AES.GCM.Nonce(data: Data(iv.utf8)))
        // Form encoding: base64's + / = must not reach the server as they are.
        let plain = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let form = [("ciphertext", (box.ciphertext + box.tag).base64EncodedString()), ("iv", iv)]
            .map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: plain)!)" }.joined(separator: "&")
        var r = URLRequest(url: endpoint, timeoutInterval: 15)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = Data(form.utf8)
        return r
    }

    /// GCM needs a new IV for every message; Bark wants it as 12 characters.
    static func randomIV() -> String {
        String((0..<12).map { _ in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()! })
    }
}

/// cfind > Settings (⌘,).
struct PhonePushSettings: View {
    @AppStorage(PhonePush.urlKey) private var url = ""
    @AppStorage(PhonePush.keyKey) private var key = ""
    @AppStorage(PhonePush.statusKey) private var status = ""
    @State private var sending = false

    var body: some View {
        Form {
            Section {
                TextField("Bark URL", text: $url, prompt: Text("https://api.day.app/YOUR_KEY"))
                SecureField("Encryption key", text: $key, prompt: Text("32 characters"))
                LabeledContent("Last push") {
                    HStack {
                        Text(status.isEmpty ? "None yet" : status).foregroundStyle(.secondary).lineLimit(2)
                        Button("Send test") {
                            sending = true
                            Task {
                                status = await PhonePush.post(title: "cfind", body: "Test from your Mac", link: nil, url: url, key: key)
                                sending = false
                            }
                        }
                        .disabled(url.isEmpty || sending)
                    }
                }
            } header: {
                Text("iPhone notifications")
            } footer: {
                Text("While you are away from the Mac (2 minutes without input, or the screen is locked), cfind also sends its notifications to the Bark app on your iPhone. In Bark, turn on Push Encryption with AES256, GCM, noPadding, the same key, and any 12-character IV (cfind sends a new one with each push). Bark's server sees only encrypted text.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}
#endif
