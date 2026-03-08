import SwiftUI
import CoreKit

struct NewSessionAdvancedSection: View {
    @ObservedObject var viewModel: NewSessionViewModel
    let serverURLString: String
    let token: String
    @Binding var showExistingSessionsSheet: Bool
    let focusedField: FocusState<FocusedField?>.Binding
    let selectedModelDisplayValue: String
    let existingSessionButtonTitle: String?
    let existingSessionErrorMessage: String?
    let existingSessionSelectionID: String?
    let existingSessionSelectionLabel: String?
    let existingSessionSelectionClearAction: () -> Void
    let loadExistingSessionsAction: () async -> Void

    var body: some View {
        Section("Advanced") {
            modelsContent

            reasoningEffortMenu

            existingSessionSelection

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

        if !viewModel.availableModels.isEmpty {
            Menu {
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

    @ViewBuilder
    private var reasoningEffortMenu: some View {
        if !viewModel.availableReasoningEfforts.isEmpty {
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
    }

    @ViewBuilder
    private var existingSessionSelection: some View {
        if let existingSessionButtonTitle {
            Group {
                Button(existingSessionButtonTitle) {
                    showExistingSessionsSheet = true
                    Task {
                        await loadExistingSessionsAction()
                    }
                }
                .disabled(
                    viewModel.selectedMachineID == nil ||
                        viewModel.isLoadingCodexThreads ||
                        viewModel.isLoadingMoreCodexThreads ||
                        viewModel.isLoadingClaudeSessions ||
                        viewModel.isLoadingMoreClaudeSessions
                )

                if let error = existingSessionErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if let existingSessionSelectionID, let existingSessionSelectionLabel {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(existingSessionSelectionLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(existingSessionSelectionID)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                        Button("Clear Selection") {
                            existingSessionSelectionClearAction()
                        }
                        .font(.footnote)
                    }
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
    let onSpawned: () -> Void
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
                        onSpawned()
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
                            onSpawned()
                            onDismiss()
                        }
                    }
                }
                .disabled(viewModel.isSpawning)
            }
        }
    }
}

struct ProjectSelectionActionSection: View {
    @ObservedObject var viewModel: NewSessionViewModel
    let onOpenProject: () -> Void

    var body: some View {
        Section("Action") {
            Button("Open Project") {
                onOpenProject()
            }
            .disabled(
                viewModel.selectedMachineID == nil ||
                viewModel.directoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
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
