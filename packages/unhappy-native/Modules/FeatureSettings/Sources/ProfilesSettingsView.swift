import SwiftUI
import CoreKit

@MainActor
public struct ProfilesSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @AppStorage(SessionPreferenceDefaults.codexModelKey) private var codexDefaultModel = ""
    @AppStorage(SessionPreferenceDefaults.claudeModelKey) private var claudeDefaultModel = ""
    @AppStorage(SessionPreferenceDefaults.geminiModelKey) private var geminiDefaultModel = ""
    @AppStorage(SessionPreferenceDefaults.codexReasoningKey) private var codexDefaultReasoning = ""
    @AppStorage(SessionPreferenceDefaults.claudeReasoningKey) private var claudeDefaultReasoning = ""

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
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

            Section("Direct Session Defaults") {
                sessionDefaultsBlock(
                    title: "Codex",
                    model: $codexDefaultModel,
                    reasoning: $codexDefaultReasoning,
                    reasoningOptions: ["", "low", "medium", "high", "xhigh"]
                )

                sessionDefaultsBlock(
                    title: "Claude",
                    model: $claudeDefaultModel,
                    reasoning: $claudeDefaultReasoning,
                    reasoningOptions: ["", "low", "medium", "high", "max"]
                )

                sessionDefaultsBlock(
                    title: "Gemini",
                    model: $geminiDefaultModel,
                    reasoning: .constant(""),
                    reasoningOptions: []
                )
            }

            Section("Codex Permission Modes") {
                Text("Local Config uses your local Codex CLI configuration, including ~/.codex/config.toml.")
                Text("Read Only blocks writes. Workspace Write allows workspace edits with approval policy. Full Access allows unrestricted filesystem access.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Profiles")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func sessionDefaultsBlock(
        title: String,
        model: Binding<String>,
        reasoning: Binding<String>,
        reasoningOptions: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            TextField("\(title) default model", text: model)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !reasoningOptions.isEmpty {
                Picker("\(title) reasoning", selection: reasoning) {
                    Text("Not Set").tag("")
                    ForEach(reasoningOptions.filter { !$0.isEmpty }, id: \.self) { option in
                        Text(option.capitalized).tag(option)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
