import SwiftUI
import CoreKit

@MainActor
public struct NewSessionView: View {
    private let serverURLString: String
    private let token: String
    private let onSessionSpawned: @MainActor (String?) -> Void

    @StateObject private var viewModel: NewSessionViewModel
    @Environment(\.dismiss) private var dismiss

    public init(
        serverURLString: String,
        token: String,
        makeViewModel: @escaping @MainActor () -> NewSessionViewModel,
        onSessionSpawned: @escaping @MainActor (String?) -> Void = { _ in }
    ) {
        self.serverURLString = serverURLString
        self.token = token
        self.onSessionSpawned = onSessionSpawned
        _viewModel = StateObject(wrappedValue: makeViewModel())
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Machine") {
                    if viewModel.isLoadingMachines {
                        HStack {
                            ProgressView()
                            Text("Loading machines…")
                                .foregroundStyle(.secondary)
                        }
                    } else if viewModel.machines.isEmpty {
                        Text("No machines available")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Machine", selection: machineSelectionBinding) {
                            ForEach(viewModel.machines) { machine in
                                Text(machine.id).tag(machine.id)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }

                Section("Directory") {
                    TextField("Path", text: $viewModel.directoryPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("Browse Directory") {
                        Task {
                            await viewModel.loadDirectory(
                                serverURLString: serverURLString,
                                token: token
                            )
                        }
                    }
                    .disabled(viewModel.selectedMachineID == nil || viewModel.isLoadingDirectory)

                    if viewModel.isLoadingDirectory {
                        HStack {
                            ProgressView()
                            Text("Loading directory…")
                                .foregroundStyle(.secondary)
                        }
                    } else if !viewModel.directoryEntries.isEmpty {
                        ForEach(viewModel.directoryEntries) { entry in
                            Button {
                                Task {
                                    await viewModel.selectDirectoryEntry(
                                        entry,
                                        serverURLString: serverURLString,
                                        token: token
                                    )
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: entry.type == "directory" ? "folder" : "doc.text")
                                        .foregroundStyle(entry.type == "directory" ? Color.accentColor : Color.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name)
                                            .lineLimit(1)
                                        Text(entry.type.capitalized)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if entry.type == "directory" {
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(entry.type != "directory")
                        }
                    }
                }

                Section("Agent") {
                    Picker("Agent", selection: $viewModel.selectedAgent) {
                        Text("Claude").tag(APISessionSpawnAgent.claude)
                        Text("Codex").tag(APISessionSpawnAgent.codex)
                        Text("Gemini").tag(APISessionSpawnAgent.gemini)
                    }
                }

                Section("Advanced") {
                    TextField("Codex resume thread ID (optional)", text: $viewModel.codexResumeThreadID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Claude resume session ID (optional)", text: $viewModel.claudeResumeSessionID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Session token (optional)", text: $viewModel.sessionToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Environment Variables (KEY=VALUE)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $viewModel.environmentVariablesText)
                            .font(.footnote.monospaced())
                            .frame(minHeight: 96)
                        Text("One variable per line. Empty lines and # comments are ignored.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Action") {
                    Button(viewModel.isSpawning ? "Starting…" : "Start Session") {
                        Task {
                            let success = await viewModel.startSession(
                                serverURLString: serverURLString,
                                token: token
                            )
                            if success {
                                onSessionSpawned(viewModel.spawnedSessionID)
                                dismiss()
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
                                    onSessionSpawned(viewModel.spawnedSessionID)
                                    dismiss()
                                }
                            }
                        }
                        .disabled(viewModel.isSpawning)
                    }
                }

                if let info = viewModel.infoMessage {
                    Section("Status") {
                        Text(info)
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                }
                if let error = viewModel.errorMessage {
                    Section("Error") {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task(id: "\(serverURLString)|\(token)") {
                await viewModel.loadMachines(serverURLString: serverURLString, token: token)
            }
        }
    }

    private var machineSelectionBinding: Binding<String> {
        Binding(
            get: {
                viewModel.selectedMachineID ?? viewModel.machines.first?.id ?? ""
            },
            set: { newValue in
                Task {
                    await viewModel.selectMachine(
                        newValue,
                        serverURLString: serverURLString,
                        token: token
                    )
                }
            }
        )
    }
}

#Preview {
    NewSessionView(
        serverURLString: "https://api.unhappy.im",
        token: "token",
        makeViewModel: {
            let service = URLSessionMachinesService()
            return NewSessionViewModel(
                machinesLoader: NewSessionMachinesLoadUseCase(service: service),
                directoryLister: NewSessionDirectoryListUseCase(service: service),
                spawner: NewSessionSpawnUseCase(service: service)
            )
        }
    )
}
