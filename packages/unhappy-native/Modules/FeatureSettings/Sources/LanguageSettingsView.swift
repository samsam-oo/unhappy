import SwiftUI

@MainActor
struct LanguageSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Language") {
                Picker("App Language", selection: $viewModel.selectedLanguage) {
                    ForEach(AppLanguageOption.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
            }
        }
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}
