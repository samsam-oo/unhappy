import SwiftUI

@MainActor
struct ConnectorsSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Providers") {
                LabeledContent("Codex") {
                    Text("Managed by daemon")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Claude") {
                    Text("Managed by daemon")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Gemini") {
                    Text("Managed by daemon")
                        .foregroundStyle(.secondary)
                }
            }

            Section("App Access") {
                LabeledContent("API Token") {
                    Text(hasToken ? "Configured" : "Not Configured")
                        .foregroundStyle(hasToken ? .green : .secondary)
                }
            }

            Section("Notes") {
                Text("Connector authentication is configured on daemon-side profiles or environment variables. The app only selects which agent to use.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Connectors")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hasToken: Bool {
        !viewModel.apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
