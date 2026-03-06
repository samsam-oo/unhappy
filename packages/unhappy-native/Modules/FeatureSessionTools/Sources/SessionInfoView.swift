import SwiftUI
import CoreKit
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public struct SessionInfoView: View {
    let session: APISession
    let serverURLString: String
    let token: String

    @StateObject private var viewModel: SessionToolsViewModel
    @State private var showKillConfirmation = false
    @State private var quickActionStatusMessage: String?

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
            SessionInfoOverviewSections(presentation: presentation)

            Section("Quick Actions") {
                NavigationLink {
                    SessionReviewView(
                        session: session,
                        serverURLString: serverURLString,
                        token: token,
                        makeViewModel: { viewModel }
                    )
                } label: {
                    Label("Review Diff", systemImage: "doc.text.magnifyingglass")
                }

                NavigationLink {
                    SessionFinishView(
                        session: session,
                        serverURLString: serverURLString,
                        token: token,
                        makeViewModel: { viewModel }
                    )
                } label: {
                    Label("Finish Worktree", systemImage: "checkmark.circle")
                }

                Button("Copy Session ID") {
                    copyToClipboard(session.id)
                    quickActionStatusMessage = "Copied session ID"
                }
                Button("Copy Metadata JSON") {
                    copyToClipboard(session.metadata)
                    quickActionStatusMessage = "Copied metadata"
                }
                if let agentState = session.agentState, !agentState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Copy Agent State JSON") {
                        copyToClipboard(agentState)
                        quickActionStatusMessage = "Copied agent state"
                    }
                }
                if let quickActionStatusMessage {
                    Text(quickActionStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.green)
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

            SessionInfoToolOperationsSections(
                sessionID: session.id,
                serverURLString: serverURLString,
                token: token,
                viewModel: viewModel
            )
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

private func copyToClipboard(_ value: String) {
#if canImport(UIKit)
    UIPasteboard.general.string = value
#endif
}
