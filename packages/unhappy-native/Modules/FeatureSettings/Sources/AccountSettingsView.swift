import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
struct AccountSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Authentication") {
                    Text(hasToken ? "Configured" : "Not Configured")
                        .foregroundStyle(hasToken ? .green : .secondary)
                }
                LabeledContent("Server") {
                    Text(viewModel.serverURLString)
                        .font(.footnote.monospaced())
                        .lineLimit(1)
                }
                LabeledContent("Token") {
                    Text(maskedToken)
                        .font(.footnote.monospaced())
                }
            }

            Section("Actions") {
                Button("Copy API Token") {
                    copyToClipboard(viewModel.apiToken)
                    statusMessage = "Copied API token"
                }
                .disabled(!hasToken)

                Button("Clear API Token", role: .destructive) {
                    viewModel.apiToken = ""
                    statusMessage = "Cleared API token"
                }
                .disabled(!hasToken)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }

            Section("Notes") {
                Text("OAuth/social account linking is not migrated yet in native.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hasToken: Bool {
        !viewModel.apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var maskedToken: String {
        let token = viewModel.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return "None" }
        if token.count <= 10 {
            return "••••••••"
        }
        return "\(token.prefix(4))…\(token.suffix(4))"
    }
}

private func copyToClipboard(_ value: String) {
#if canImport(UIKit)
    UIPasteboard.general.string = value
#endif
}
