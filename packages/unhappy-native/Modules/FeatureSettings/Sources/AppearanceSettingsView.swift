import SwiftUI

@MainActor
struct AppearanceSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $viewModel.selectedAppearance) {
                    ForEach(AppAppearanceOption.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}
