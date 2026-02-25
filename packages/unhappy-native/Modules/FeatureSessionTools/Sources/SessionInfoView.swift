import SwiftUI
import CoreKit

@MainActor
public struct SessionInfoView: View {
    let session: APISession
    let serverURLString: String
    let token: String

    @StateObject private var viewModel: SessionToolsViewModel
    @State private var showKillConfirmation = false

    public init(
        session: APISession,
        serverURLString: String,
        token: String,
        makeViewModel: @escaping @MainActor () -> SessionToolsViewModel
    ) {
        self.session = session
        self.serverURLString = serverURLString
        self.token = token
        _viewModel = StateObject(wrappedValue: makeViewModel())
    }

    public var body: some View {
        let presentation = SessionInfoPresentationBuilder.make(from: session)

        List {
            Section("Session") {
                LabeledContent("ID") {
                    Text(presentation.sessionID)
                        .font(.footnote.monospaced())
                }
                LabeledContent("Title") {
                    Text(presentation.title ?? "Untitled")
                        .foregroundStyle(presentation.title == nil ? .secondary : .primary)
                }
                LabeledContent("Status") {
                    Text(presentation.active ? "Active" : "Inactive")
                        .foregroundStyle(presentation.active ? Color.green : Color.secondary)
                }
                if let sequenceText = presentation.sequenceText {
                    LabeledContent("Sequence") {
                        Text(sequenceText)
                            .font(.footnote.monospaced())
                    }
                }
                LabeledContent("Created") { Text(presentation.createdAtText) }
                LabeledContent("Active At") { Text(presentation.activeAtText) }
                LabeledContent("Updated") { Text(presentation.updatedAtText) }
            }

            Section("Metadata") {
                LabeledContent("Metadata Version") {
                    Text(presentation.metadataVersionText)
                        .font(.footnote.monospaced())
                }
                if let agentStateVersionText = presentation.agentStateVersionText {
                    LabeledContent("Agent State Version") {
                        Text(agentStateVersionText)
                            .font(.footnote.monospaced())
                    }
                }
                LabeledContent("Metadata Size") {
                    Text("\(presentation.metadataCharacterCount) chars")
                        .font(.footnote.monospaced())
                }
                if let keyPreview = presentation.dataEncryptionKeyPreview {
                    LabeledContent("Data Key") {
                        Text(keyPreview)
                            .font(.footnote.monospaced())
                    }
                } else {
                    LabeledContent("Data Key") {
                        Text("None")
                            .foregroundStyle(.secondary)
                    }
                }

                if !presentation.metadataFields.isEmpty {
                    Text("Metadata Fields")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(presentation.metadataFields) { field in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.key)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(field.value)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                                .lineLimit(nil)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Text(presentation.metadataPreview)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(nil)

                if presentation.metadataTruncated {
                    Text("Metadata preview is truncated to first \(SessionInfoPresentationBuilder.metadataPreviewLimit) chars.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if presentation.agentStatePreview != nil || !presentation.agentStateFields.isEmpty {
                Section("Agent State") {
                    LabeledContent("Size") {
                        Text("\(presentation.agentStateCharacterCount) chars")
                            .font(.footnote.monospaced())
                    }
                    if !presentation.agentStateFields.isEmpty {
                        Text("Parsed Fields")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(presentation.agentStateFields) { field in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(field.key)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(field.value)
                                    .font(.footnote.monospaced())
                                    .textSelection(.enabled)
                                    .lineLimit(nil)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    if let preview = presentation.agentStatePreview {
                        Text(preview)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(nil)
                    }
                    if presentation.agentStateTruncated {
                        Text("Agent state preview is truncated to first \(SessionInfoPresentationBuilder.metadataPreviewLimit) chars.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Actions") {
                Button("Kill Session Process", role: .destructive) {
                    showKillConfirmation = true
                }
                .disabled(viewModel.isKillingSession)

                if viewModel.isKillingSession {
                    ProgressView("Killing session…")
                }
                if let status = viewModel.killStatusMessage {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
                if let error = viewModel.killErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Task Control") {
                TextField("Abort reason (optional)", text: $viewModel.abortReason)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(viewModel.isAbortingTask ? "Sending…" : "Abort Current Task") {
                    Task {
                        await viewModel.abortTask(
                            sessionID: session.id,
                            serverURLString: serverURLString,
                            token: token
                        )
                    }
                }
                .disabled(viewModel.isAbortingTask)

                if let status = viewModel.abortStatusMessage {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
                if let error = viewModel.abortErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Permission") {
                TextField("Permission request ID", text: $viewModel.permissionRequestID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Decision", selection: $viewModel.permissionDecision) {
                    ForEach(APISessionPermissionDecision.allCases, id: \.self) { decision in
                        Text(decision.label).tag(decision)
                    }
                }
                Picker("Mode", selection: $viewModel.permissionMode) {
                    ForEach(APISessionPermissionMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                TextField("Allow tools (comma-separated)", text: $viewModel.permissionAllowTools)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button(viewModel.isSubmittingPermission ? "Sending…" : "Send Permission Response") {
                    Task {
                        await viewModel.submitPermissionDecision(
                            sessionID: session.id,
                            serverURLString: serverURLString,
                            token: token
                        )
                    }
                }
                .disabled(
                    viewModel.isSubmittingPermission ||
                    viewModel.permissionRequestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                if let status = viewModel.permissionStatusMessage {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
                if let error = viewModel.permissionErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Execution Mode") {
                Picker("Target", selection: $viewModel.switchTarget) {
                    ForEach(APISessionSwitchTarget.allCases, id: \.self) { target in
                        Text(target.label).tag(target)
                    }
                }

                Button(viewModel.isSwitchingMode ? "Switching…" : "Apply Mode Switch") {
                    Task {
                        await viewModel.switchMode(
                            sessionID: session.id,
                            serverURLString: serverURLString,
                            token: token
                        )
                    }
                }
                .disabled(viewModel.isSwitchingMode)

                if let status = viewModel.switchStatusMessage {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
                if let error = viewModel.switchErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Bash") {
                TextField("Command", text: $viewModel.bashCommand, axis: .vertical)
                    .lineLimit(2...4)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Working directory (optional)", text: $viewModel.bashWorkingDirectory)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Timeout ms (optional)", text: $viewModel.bashTimeoutMilliseconds)
                    .keyboardType(.numberPad)
                Button(viewModel.isRunningBash ? "Running…" : "Run Bash") {
                    Task {
                        await viewModel.runBash(
                            sessionID: session.id,
                            serverURLString: serverURLString,
                            token: token
                        )
                    }
                }
                .disabled(
                    viewModel.isRunningBash ||
                    viewModel.bashCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                if let exitCode = viewModel.bashExitCode {
                    Text("Exit code: \(exitCode)")
                        .font(.footnote.monospaced())
                        .foregroundStyle(exitCode == 0 ? .green : .secondary)
                }
                if let error = viewModel.bashErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if !viewModel.bashStdout.isEmpty {
                    LabeledContent("stdout") {
                        Text(viewModel.bashStdout)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(nil)
                    }
                }
                if !viewModel.bashStderr.isEmpty {
                    LabeledContent("stderr") {
                        Text(viewModel.bashStderr)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Ripgrep") {
                TextField("Args (e.g. TODO Sources)", text: $viewModel.ripgrepArgs)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Working directory (optional)", text: $viewModel.ripgrepWorkingDirectory)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(viewModel.isRunningRipgrep ? "Running…" : "Run Ripgrep") {
                    Task {
                        await viewModel.runRipgrep(
                            sessionID: session.id,
                            serverURLString: serverURLString,
                            token: token
                        )
                    }
                }
                .disabled(
                    viewModel.isRunningRipgrep ||
                    viewModel.ripgrepArgs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                if let exitCode = viewModel.ripgrepExitCode {
                    Text("Exit code: \(exitCode)")
                        .font(.footnote.monospaced())
                        .foregroundStyle(exitCode == 0 ? .green : .secondary)
                }
                if let error = viewModel.ripgrepErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if !viewModel.ripgrepStdout.isEmpty {
                    LabeledContent("stdout") {
                        Text(viewModel.ripgrepStdout)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(nil)
                    }
                }
                if !viewModel.ripgrepStderr.isEmpty {
                    LabeledContent("stderr") {
                        Text(viewModel.ripgrepStderr)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Difftastic") {
                TextField("Args (e.g. --display inline HEAD~1 HEAD)", text: $viewModel.difftasticArgs)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Working directory (optional)", text: $viewModel.difftasticWorkingDirectory)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(viewModel.isRunningDifftastic ? "Running…" : "Run Difftastic") {
                    Task {
                        await viewModel.runDifftastic(
                            sessionID: session.id,
                            serverURLString: serverURLString,
                            token: token
                        )
                    }
                }
                .disabled(
                    viewModel.isRunningDifftastic ||
                    viewModel.difftasticArgs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                if let exitCode = viewModel.difftasticExitCode {
                    Text("Exit code: \(exitCode)")
                        .font(.footnote.monospaced())
                        .foregroundStyle(exitCode == 0 ? .green : .secondary)
                }
                if let error = viewModel.difftasticErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if !viewModel.difftasticStdout.isEmpty {
                    LabeledContent("stdout") {
                        Text(viewModel.difftasticStdout)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(nil)
                    }
                }
                if !viewModel.difftasticStderr.isEmpty {
                    LabeledContent("stderr") {
                        Text(viewModel.difftasticStderr)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Session Info")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Kill session process?",
            isPresented: $showKillConfirmation,
            actions: {
                Button("Cancel", role: .cancel) {}
                Button("Kill", role: .destructive) {
                    Task {
                        await viewModel.killSession(
                            sessionID: session.id,
                            serverURLString: serverURLString,
                            token: token
                        )
                    }
                }
            },
            message: {
                Text("This immediately stops the agent process for this session.")
            }
        )
    }
}

private extension APISessionPermissionDecision {
    var label: String {
        switch self {
        case .approved:
            return "Approve"
        case .approvedForSession:
            return "Approve for Session"
        case .denied:
            return "Deny"
        case .abort:
            return "Abort"
        }
    }
}

private extension APISessionPermissionMode {
    var label: String {
        switch self {
        case .default:
            return "Default"
        case .acceptEdits:
            return "Accept Edits"
        case .bypassPermissions:
            return "Bypass Permissions"
        case .plan:
            return "Plan"
        }
    }
}

private extension APISessionSwitchTarget {
    var label: String {
        switch self {
        case .remote:
            return "Remote"
        case .local:
            return "Local"
        }
    }
}
