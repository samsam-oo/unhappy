import SwiftUI
import CoreKit

struct NewSessionAdvancedSection: View {
    @ObservedObject var viewModel: NewSessionViewModel
    let serverURLString: String
    let token: String
    @Binding var showCodexThreadsSheet: Bool
    @Binding var showClaudeSessionsSheet: Bool
    let focusedField: FocusState<FocusedField?>.Binding
    let selectedModelDisplayValue: String
    let codexSelectionButtonTitle: String
    let claudeSelectionButtonTitle: String

    var body: some View {
        Section("Advanced") {
            modelsContent

            reasoningEffortMenu

            codexSessionSelection
            claudeSessionSelection

            TextField("Session token (optional)", text: $viewModel.sessionToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(focusedField, equals: .sessionToken)
            environmentVariablesEditor
        }
    }

    @ViewBuilder
    private var modelsContent: some View {
        if viewModel.isLoadingModels {
            HStack {
                ProgressView()
                Text("Loading models…")
                    .foregroundStyle(.secondary)
            }
        }

        Menu {
            Button("Default") {
                viewModel.setSelectedModel("")
            }
            ForEach(viewModel.availableModels, id: \.self) { model in
                Button(model) {
                    viewModel.setSelectedModel(model)
                }
            }
        } label: {
            HStack {
                Text("Model")
                Spacer()
                Text(selectedModelDisplayValue)
                    .foregroundStyle(.secondary)
            }
        }

        if let error = viewModel.modelsErrorMessage {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.red)
            Button("Retry Models") {
                Task {
                    await viewModel.loadModels(
                        serverURLString: serverURLString,
                        token: token
                    )
                }
            }
            .font(.footnote)
        }
    }

    private var reasoningEffortMenu: some View {
        Menu {
            ForEach(viewModel.availableReasoningEfforts, id: \.rawValue) { value in
                Button(value.displayName) {
                    viewModel.setSelectedReasoningEffort(value)
                }
            }
        } label: {
            HStack {
                Text("Reasoning Effort")
                Spacer()
                Text(viewModel.selectedReasoningEffort.displayName)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var codexSessionSelection: some View {
        Group {
            Button(viewModel.isLoadingCodexThreads ? "Loading Codex Sessions…" : codexSelectionButtonTitle) {
                showCodexThreadsSheet = true
                Task {
                    await viewModel.loadCodexThreads(
                        serverURLString: serverURLString,
                        token: token
                    )
                }
            }
            .disabled(
                viewModel.selectedMachineID == nil ||
                    viewModel.isLoadingCodexThreads ||
                    viewModel.isLoadingMoreCodexThreads
            )

            if let error = viewModel.codexThreadsErrorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if !viewModel.codexResumeThreadID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected Codex Session")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.codexResumeThreadID)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    Button("Clear Codex Selection") {
                        viewModel.clearCodexSelection()
                    }
                    .font(.footnote)
                }
            }
        }
    }

    private var claudeSessionSelection: some View {
        Group {
            Button(viewModel.isLoadingClaudeSessions ? "Loading Claude Sessions…" : claudeSelectionButtonTitle) {
                showClaudeSessionsSheet = true
                Task {
                    await viewModel.loadClaudeSessions(
                        serverURLString: serverURLString,
                        token: token
                    )
                }
            }
            .disabled(
                viewModel.selectedMachineID == nil ||
                    viewModel.isLoadingClaudeSessions ||
                    viewModel.isLoadingMoreClaudeSessions
            )

            if let error = viewModel.claudeSessionsErrorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if !viewModel.claudeResumeSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected Claude Session")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.claudeResumeSessionID)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    Button("Clear Claude Selection") {
                        viewModel.clearClaudeSelection()
                    }
                    .font(.footnote)
                }
            }
        }
    }

    private var environmentVariablesEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Environment Variables (KEY=VALUE)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $viewModel.environmentVariablesText)
                .font(.footnote.monospaced())
                .frame(minHeight: 96)
                .focused(focusedField, equals: .environmentVariables)
            Text("One variable per line. Empty lines and # comments are ignored.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct NewSessionActionSection: View {
    @ObservedObject var viewModel: NewSessionViewModel
    let serverURLString: String
    let token: String
    let primaryActionTitle: String
    let onSpawned: (String?) -> Void
    let onDismiss: () -> Void

    var body: some View {
        Section("Action") {
            Button(viewModel.isSpawning ? "Starting…" : primaryActionTitle) {
                Task {
                    let success = await viewModel.startSession(
                        serverURLString: serverURLString,
                        token: token
                    )
                    if success {
                        onSpawned(viewModel.spawnedSessionID)
                        onDismiss()
                    }
                }
            }
            .disabled(
                viewModel.isSpawning ||
                    viewModel.selectedMachineID == nil ||
                    viewModel.directoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )

            if let approvalDirectory = viewModel.approvalDirectory {
                Text("Directory creation approval needed: \(approvalDirectory)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Create Directory And Continue") {
                    Task {
                        let success = await viewModel.continueWithDirectoryApproval(
                            serverURLString: serverURLString,
                            token: token
                        )
                        if success {
                            onSpawned(viewModel.spawnedSessionID)
                            onDismiss()
                        }
                    }
                }
                .disabled(viewModel.isSpawning)
            }
        }
    }
}

struct NewSessionStatusSections: View {
    let infoMessage: String?
    let errorMessage: String?

    var body: some View {
        if let infoMessage {
            Section("Status") {
                Text(infoMessage)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
        }
        if let errorMessage {
            Section("Error") {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }
}
