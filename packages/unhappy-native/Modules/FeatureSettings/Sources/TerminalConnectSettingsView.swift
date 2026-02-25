import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
struct TerminalConnectSettingsView: View {
    @State private var authURLString = ""
    @State private var statusMessage: String?

    private var parsedRequest: TerminalAuthRequest? {
        TerminalAuthURLParser.parse(authURLString)
    }

    var body: some View {
        Form {
            Section("Connection URL") {
                TextField("unhappy://terminal?...", text: $authURLString, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())

                Text("Paste the terminal auth URL from daemon or CLI.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Request Preview") {
                if let parsedRequest {
                    LabeledContent("Type") {
                        Text("Terminal Auth")
                    }
                    LabeledContent("Public Key") {
                        Text(keyPreview(for: parsedRequest.publicKey))
                            .font(.footnote.monospaced())
                    }
                } else {
                    if authURLString.isEmpty {
                        Text("Enter a URL to preview.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Invalid terminal auth URL.")
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("Actions") {
                Button("Copy Public Key") {
                    guard let publicKey = parsedRequest?.publicKey else { return }
                    copyToClipboard(publicKey)
                    statusMessage = "Copied public key"
                }
                .disabled(parsedRequest == nil)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }

            Section("Notes") {
                Text("Native terminal approval handshake is not migrated yet. This screen validates and previews incoming terminal URLs.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Terminal Connect")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func keyPreview(for key: String) -> String {
        if key.count <= 20 {
            return key
        }
        return "\(key.prefix(12))...\(key.suffix(8))"
    }
}

private func copyToClipboard(_ value: String) {
#if canImport(UIKit)
    UIPasteboard.general.string = value
#endif
}
