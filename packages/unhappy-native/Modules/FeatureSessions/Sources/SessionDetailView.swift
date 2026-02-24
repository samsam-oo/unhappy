import SwiftUI
import CoreKit

@MainActor
public struct SessionDetailView: View {
    let session: APISession
    @ObservedObject var viewModel: SessionsViewModel
    let serverURLString: String
    let token: String

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false

    public init(
        session: APISession,
        viewModel: SessionsViewModel,
        serverURLString: String,
        token: String
    ) {
        self.session = session
        self.viewModel = viewModel
        self.serverURLString = serverURLString
        self.token = token
    }

    public var body: some View {
        List {
            Section("Session") {
                LabeledContent("ID") {
                    Text(session.id)
                        .font(.footnote.monospaced())
                }
                LabeledContent("Status") {
                    Text(session.active ? "Active" : "Inactive")
                        .foregroundStyle(session.active ? Color.green : Color.secondary)
                }
                LabeledContent("Updated") {
                    Text(Date(timeIntervalSince1970: session.updatedAt), style: .relative)
                }
            }

            Section("Messages") {
                if viewModel.isLoadingSessionMessages {
                    ProgressView("Loading messages…")
                } else if let error = viewModel.selectedSessionErrorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Unable to load messages")
                            .font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Retry") {
                            Task {
                                await viewModel.loadMessages(
                                    for: session.id,
                                    serverURLString: serverURLString,
                                    token: token
                                )
                            }
                        }
                    }
                    .padding(.vertical, 8)
                } else if viewModel.selectedSessionMessages.isEmpty {
                    Text("No messages")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.selectedSessionMessages) { message in
                        SessionMessageRow(message: message)
                    }
                }
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isDeleting(sessionID: session.id) {
                    ProgressView()
                } else {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .task(id: session.id) {
            await viewModel.loadMessages(
                for: session.id,
                serverURLString: serverURLString,
                token: token
            )
        }
        .refreshable {
            await viewModel.loadMessages(
                for: session.id,
                serverURLString: serverURLString,
                token: token
            )
        }
        .onDisappear {
            viewModel.clearDetailSelectionIfNeeded(sessionID: session.id)
        }
        .alert(
            "Delete session?",
            isPresented: $showDeleteConfirmation,
            actions: {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.deleteSession(
                            sessionID: session.id,
                            serverURLString: serverURLString,
                            token: token
                        )
                        if !viewModel.sessions.contains(where: { $0.id == session.id }) {
                            dismiss()
                        }
                    }
                }
            },
            message: {
                Text("This removes the session permanently from the server.")
            }
        )
    }
}

private struct SessionMessageRow: View {
    let message: APISessionMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("#\(message.seq)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Date(timeIntervalSince1970: message.createdAt), style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(message.id)
                .font(.footnote.monospaced())
                .lineLimit(1)

            if let content = message.content {
                Text("Content: \(content.t) • \(content.c.count) chars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Content: empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
