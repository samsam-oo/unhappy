import SwiftUI

@MainActor
struct VoiceSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Voice") {
                Toggle("Enable voice responses", isOn: $viewModel.voiceEnabled)
                NavigationLink {
                    VoiceLanguageSettingsView(viewModel: viewModel)
                } label: {
                    LabeledContent("Language") {
                        Text(viewModel.voiceLanguage.label)
                    }
                }
            }

            Section("Notes") {
                Text("Voice language controls preferred voice locale for future speech features.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
    }
}
