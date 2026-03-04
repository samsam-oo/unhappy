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
            Section("Session") {
                LabeledContent("ID") {
                    Text(presentation.sessionID)
                        .font(.footnote.monospaced())
                }
                LabeledContent("Title") {
                    Text(presentation.title)
                        .foregroundStyle(presentation.isFallbackTitle ? .secondary : .primary)
                }
                if let machineDisplayName = presentation.machineDisplayName {
                    LabeledContent("Machine") {
                        Text(machineDisplayName)
                            .lineLimit(1)
                    }
                }
                if let machineIdentifier = presentation.machineIdentifier {
                    LabeledContent("Machine ID") {
                        Text(machineIdentifier)
                            .font(.footnote.monospaced())
                    }
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
