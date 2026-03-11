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
    @State private var showDeleteMachineConfirmation = false
    @Environment(\.dismiss) private var dismiss

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
        let currentMachine = viewModel.machine(machineID: machine.id) ?? machine
        let presentation = MachineDetailPresentationBuilder.make(from: currentMachine)
        let machineDisplayName = MachineDisplayNameResolver.displayName(for: currentMachine)
        List {
            machineSection(machine: currentMachine, machineDisplayName: machineDisplayName, presentation: presentation)
            daemonDiagnosticsSection(presentation: presentation)
            metadataDiagnosticsSection(presentation: presentation)
            spawnSessionSection(machine: currentMachine)
            daemonSection(machine: currentMachine)
            statusSection
            errorSection
        }
        .navigationTitle(machineDisplayName == currentMachine.id ? "Machine" : machineDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Stop daemon?",
            isPresented: $showStopDaemonConfirmation,
            actions: {
                Button("Cancel", role: .cancel) {}
                Button("Stop", role: .destructive) {
                    Task {
                        await viewModel.stopDaemon(
                            machineID: currentMachine.id,
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
        .alert(
            "Delete offline machine?",
            isPresented: $showDeleteMachineConfirmation,
            actions: {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        await deleteMachine()
                    }
                }
            },
            message: {
                Text("This removes the offline machine record from your account.")
            }
        )
    }

    private func machineSection(
        machine: APIMachine,
        machineDisplayName: String,
        presentation: MachineDetailPresentation
    ) -> some View {
        Section("Machine") {
            LabeledContent("Name") {
                Text(machineDisplayName)
                    .lineLimit(1)
            }
            LabeledContent("ID") {
                Text(machine.id)
                    .font(.footnote.monospaced())
            }
            LabeledContent("Status") {
                Text(presentation.statusText)
                    .foregroundStyle(machine.active ? Color.green : (machine.isExplicitlyStopped ? Color.orange : Color.secondary))
            }
            LabeledContent("Active At") {
                Text(presentation.activeAtText)
            }
            if let stoppedAtText = presentation.stoppedAtText {
                LabeledContent("Stopped At") {
                    Text(stoppedAtText)
                }
            }
            LabeledContent("Created At") {
                Text(presentation.createdAtText)
            }
            LabeledContent("Updated At") {
                Text(presentation.updatedAtText)
            }
        }
    }

    @ViewBuilder
    private func daemonDiagnosticsSection(
        presentation: MachineDetailPresentation
    ) -> some View {
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
    }

    private func metadataDiagnosticsSection(
        presentation: MachineDetailPresentation
    ) -> some View {
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
    }

    @ViewBuilder
    private func spawnSessionSection(machine: APIMachine) -> some View {
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
                Task { await spawnSession(directory: directory, approvedNewDirectoryCreation: false) }
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
                    Task { await spawnSession(directory: approvalDirectory, approvedNewDirectoryCreation: true) }
                }
                .disabled(viewModel.isSpawning(machineID: machine.id))
            }

            if let sessionID = viewModel.spawnedSessionID(machineID: machine.id) {
                Text("Spawned session: \(sessionID)")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
        }
    }

    private func daemonSection(machine: APIMachine) -> some View {
        Section("Daemon") {
            Button("Update Daemon") {
                Task { await updateDaemon() }
            }
            .disabled(viewModel.isUpdating(machineID: machine.id))

            Button(
                viewModel.preventSleepEnabled(machineID: machine.id)
                    ? "Disable Prevent Sleep"
                    : "Enable Prevent Sleep"
            ) {
                Task {
                    await viewModel.setPreventSleep(
                        machineID: machine.id,
                        enabled: !viewModel.preventSleepEnabled(machineID: machine.id),
                        serverURLString: serverURLString,
                        token: token
                    )
                }
            }
            .disabled(viewModel.isTogglingPreventSleep(machineID: machine.id))

            Button("Stop Daemon", role: .destructive) {
                showStopDaemonConfirmation = true
            }
            .disabled(viewModel.isStopping(machineID: machine.id))

            if !machine.active {
                Button("Delete Machine", role: .destructive) {
                    showDeleteMachineConfirmation = true
                }
                .disabled(viewModel.isDeleting(machineID: machine.id))
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let status = viewModel.status(machineID: machine.id) {
            Section("Status") {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = viewModel.error(machineID: machine.id) {
            Section("Error") {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func spawnSession(directory: String, approvedNewDirectoryCreation: Bool) async {
        await viewModel.spawnSession(
            machineID: machine.id,
            wrappedMachineDataEncryptionKey: machine.dataEncryptionKey,
            directory: directory,
            serverURLString: serverURLString,
            token: token,
            agent: selectedAgent,
            approvedNewDirectoryCreation: approvedNewDirectoryCreation
        )
    }

    private func updateDaemon() async {
        await viewModel.updateDaemon(
            machineID: machine.id,
            serverURLString: serverURLString,
            token: token
        )
    }

    private func deleteMachine() async {
        await viewModel.deleteMachine(
            machineID: machine.id,
            serverURLString: serverURLString,
            token: token
        )
        if viewModel.error(machineID: machine.id) == nil {
            dismiss()
        }
    }
}
