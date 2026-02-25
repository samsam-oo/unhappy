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
