import SwiftUI
import CoreKit

@MainActor
public struct MachineDetailView: View {
    let machine: APIMachine
    @ObservedObject var viewModel: MachinesViewModel
    let serverURLString: String
    let token: String

    @State private var directory: String = "~"
    @State private var selectedAgent: APISessionSpawnAgent = .claude
    @State private var showStopDaemonConfirmation = false

    public init(
        machine: APIMachine,
        viewModel: MachinesViewModel,
        serverURLString: String,
        token: String
    ) {
        self.machine = machine
        self.viewModel = viewModel
        self.serverURLString = serverURLString
        self.token = token
    }

    public var body: some View {
        let presentation = MachineDetailPresentationBuilder.make(from: machine)
        List {
            Section("Machine") {
                LabeledContent("ID") {
                    Text(machine.id)
                        .font(.footnote.monospaced())
                }
                LabeledContent("Status") {
                    Text(machine.active ? "Online" : "Offline")
                        .foregroundStyle(machine.active ? Color.green : Color.secondary)
                }
                LabeledContent("Active At") {
                    Text(presentation.activeAtText)
                }
                LabeledContent("Created At") {
                    Text(presentation.createdAtText)
                }
                LabeledContent("Updated At") {
                    Text(presentation.updatedAtText)
                }
            }

            Section("Daemon Diagnostics") {
                LabeledContent("Daemon State Version") {
                    Text(presentation.daemonStateVersionText)
                }

                if !presentation.daemonStateFields.isEmpty {
                    ForEach(presentation.daemonStateFields) { field in
                        LabeledContent(field.key) {
                            Text(field.value)
                                .font(.footnote.monospaced())
                                .lineLimit(2)
                        }
                    }
                }

                if let daemonStatePreview = presentation.daemonStatePreview {
                    Text(daemonStatePreview)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    if presentation.daemonStateTruncated {
                        Text("Daemon state preview truncated")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No daemon state payload")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Metadata Diagnostics") {
                LabeledContent("Metadata Version") {
                    Text(presentation.metadataVersionText)
                }
                if !presentation.metadataFields.isEmpty {
                    ForEach(presentation.metadataFields) { field in
                        LabeledContent(field.key) {
                            Text(field.value)
                                .font(.footnote.monospaced())
                                .lineLimit(2)
                        }
                    }
                }

                Text(presentation.metadataPreview)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                if presentation.metadataTruncated {
                    Text("Metadata preview truncated")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Spawn Session") {
                TextField("Directory", text: $directory)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Agent", selection: $selectedAgent) {
                    Text("Claude").tag(APISessionSpawnAgent.claude)
                    Text("Codex").tag(APISessionSpawnAgent.codex)
                    Text("Gemini").tag(APISessionSpawnAgent.gemini)
                }

                Button("Start Session") {
                    Task {
                        await viewModel.spawnSession(
                            machineID: machine.id,
                            directory: directory,
                            serverURLString: serverURLString,
                            token: token,
                            agent: selectedAgent
                        )
                    }
                }
                .disabled(
                    viewModel.isSpawning(machineID: machine.id) ||
                    directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                if let approvalDirectory = viewModel.approvalDirectory(machineID: machine.id) {
                    Text("Directory creation approval needed: \(approvalDirectory)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Create Directory And Continue") {
                        Task {
                            await viewModel.spawnSession(
                                machineID: machine.id,
                                directory: approvalDirectory,
                                serverURLString: serverURLString,
                                token: token,
                                agent: selectedAgent,
                                approvedNewDirectoryCreation: true
                            )
                        }
                    }
                    .disabled(viewModel.isSpawning(machineID: machine.id))
                }

                if let sessionID = viewModel.spawnedSessionID(machineID: machine.id) {
                    Text("Spawned session: \(sessionID)")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }

            Section("Daemon") {
                Button("Update Daemon") {
                    Task {
                        await viewModel.updateDaemon(
                            machineID: machine.id,
                            serverURLString: serverURLString,
                            token: token
                        )
                    }
                }
                .disabled(viewModel.isUpdating(machineID: machine.id))

                Button("Stop Daemon", role: .destructive) {
                    showStopDaemonConfirmation = true
                }
                .disabled(viewModel.isStopping(machineID: machine.id))
            }

            if let status = viewModel.status(machineID: machine.id) {
                Section("Status") {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }
            if let error = viewModel.error(machineID: machine.id) {
                Section("Error") {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Machine")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Stop daemon?",
            isPresented: $showStopDaemonConfirmation,
            actions: {
                Button("Cancel", role: .cancel) {}
                Button("Stop", role: .destructive) {
                    Task {
                        await viewModel.stopDaemon(
                            machineID: machine.id,
                            serverURLString: serverURLString,
                            token: token
                        )
                    }
                }
            },
            message: {
                Text("This stops the machine daemon process.")
            }
        )
    }
}
