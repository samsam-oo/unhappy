import SwiftUI

@MainActor
struct VoiceLanguageSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Voice Language") {
                Picker("Language", selection: $viewModel.voiceLanguage) {
                    ForEach(AppVoiceLanguageOption.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
            }
        }
        .navigationTitle("Voice Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}
