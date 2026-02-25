import SwiftUI
import CoreKit

@MainActor
struct ProfilesSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Default Agent Profile") {
                Picker("Agent", selection: $viewModel.defaultNewSessionAgent) {
                    Text("Claude").tag(APISessionSpawnAgent.claude)
                    Text("Codex").tag(APISessionSpawnAgent.codex)
                    Text("Gemini").tag(APISessionSpawnAgent.gemini)
                }
            }

            Section("Notes") {
                Text("This default is applied when opening New Session.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Profiles")
        .navigationBarTitleDisplayMode(.inline)
    }
}
