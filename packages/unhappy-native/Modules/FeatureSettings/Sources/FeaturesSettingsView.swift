import SwiftUI

@MainActor
struct FeaturesSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Experimental Features") {
                Toggle("Enable experiments", isOn: $viewModel.experimentsEnabled)
                Toggle("Hide inactive sessions", isOn: $viewModel.hideInactiveSessions)
                Toggle("Use enhanced new-session wizard", isOn: $viewModel.useEnhancedSessionWizard)
            }

            Section("Notes") {
                Text("These flags are stored locally and may change behavior between releases.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .navigationTitle("Features")
        .navigationBarTitleDisplayMode(.inline)
    }
}
