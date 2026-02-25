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
        List {
            Section("Session") {
                LabeledContent("ID") {
                    Text(session.id)
                        .font(.footnote.monospaced())
                }
                LabeledContent("Title") {
                    Text(session.displayName ?? "Untitled")
                        .foregroundStyle(session.displayName == nil ? .secondary : .primary)
                }
                LabeledContent("Status") {
                    Text(session.active ? "Active" : "Inactive")
                        .foregroundStyle(session.active ? Color.green : Color.secondary)
                }
                LabeledContent("Updated") {
                    Text(Date(timeIntervalSince1970: session.updatedAt), style: .relative)
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
