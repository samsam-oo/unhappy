import SwiftUI

@MainActor
public struct VoiceSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
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
