#if os(iOS)
import SwiftUI
import UIKit

struct PairView: View {
    @Environment(AppModel.self) private var model
    @State private var address = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "laptopcomputer.and.iphone")
                            .font(.system(size: 34))
                            .foregroundStyle(.tint)
                        Text("Pair with your Mac").font(.title2.bold())
                        Text("On the Mac, open the cfind dashboard, go to Connections, and choose Pair an iPhone.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                if model.revoked && model.link == nil {
                    Section {
                        Label("This iPhone was removed on the Mac. Pair it again.", systemImage: "exclamationmark.triangle")
                    }
                }
                Section {
                    PasteButton(payloadType: String.self) { strings in
                        let text = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        guard let url = URL(string: text), let link = PairLink(url) else {
                            error = "That is not a cfind pairing link"
                            return
                        }
                        fill(link)
                    }
                } footer: {
                    Text("Copy the link on the Mac, then paste it here.")
                }
                Section("Or type it") {
                    TextField("Mac address", text: $address, prompt: Text("https://your-mac.tailnet.ts.net"))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("pair-address")
                    TextField("Code", text: $code, prompt: Text("6-digit code"))
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("pair-code")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button {
                        Task { await pair() }
                    } label: {
                        HStack {
                            Text("Pair")
                            if busy { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(busy || digits.count != 6 || base == nil)
                    .accessibilityIdentifier("pair-button")
                }
            }
            .navigationTitle("cfind")
            .toolbar {
                if model.link != nil && model.pairing != nil && !model.revoked {
                    Button("Cancel") { model.link = nil }
                }
            }
            .onAppear { if let link = model.link { fill(link) } }
            .onChange(of: model.link) { _, link in if let link { fill(link) } }
        }
    }

    var digits: String { code.filter(\.isNumber) }

    /// "mac.tailnet.ts.net" alone means HTTPS.
    var base: URL? {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(string: text.contains("://") ? text : "https://" + text)
        return url?.host() == nil ? nil : url
    }

    func fill(_ link: PairLink) {
        address = link.base.absoluteString
        code = link.code
        error = nil
    }

    func pair() async {
        guard let base else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            model.paired(try await API.pair(base: base, code: digits, name: UIDevice.current.name))
        } catch {
            self.error = error.localizedDescription
        }
    }
}
#endif
