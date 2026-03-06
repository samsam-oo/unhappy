import SwiftUI

@MainActor
public struct FeaturesSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @AppStorage("unhappy.native.showReasoningDetails")
    private var showReasoningDetails = false

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            Section("Experimental Features") {
                Toggle("Enable experiments", isOn: $viewModel.experimentsEnabled)
                Toggle("Hide inactive sessions", isOn: $viewModel.hideInactiveSessions)
                Toggle("Use enhanced new-session wizard", isOn: $viewModel.useEnhancedSessionWizard)
                Toggle("Show reasoning details in transcript", isOn: $showReasoningDetails)
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
