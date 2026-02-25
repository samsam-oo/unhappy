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
    @State private var showRenameSheet = false
    @State private var showCodexThreadsSheet = false
    @State private var showClaudeSessionsSheet = false
    @State private var renameDraft = ""
    @State private var codexCwdFilterDraft = ""
    @State private var claudeCwdFilterDraft = ""
    @State private var claudeResumeDirectoryDraft = ""

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
            Section("Multi-Agent") {
                HStack {
                    Text(viewModel.activeSessionsCount == 1 ? "1 active session" : "\(viewModel.activeSessionsCount) active sessions")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(viewModel.multiAgentInProgress ? "진행중" : "완료됨")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(viewModel.multiAgentInProgress ? Color.green.opacity(0.16) : Color.gray.opacity(0.14))
                        .foregroundStyle(viewModel.multiAgentInProgress ? Color.green : Color.secondary)
                        .clipShape(Capsule())
                }
            }

            Section("Session") {
                LabeledContent("Title") {
                    Text(currentSession.displayName ?? "Untitled")
                        .foregroundStyle(currentSession.displayName == nil ? .secondary : .primary)
                }
                LabeledContent("ID") {
                    Text(currentSession.id)
                        .font(.footnote.monospaced())
                }
                LabeledContent("Status") {
                    Text(currentSession.active ? "Active" : "Inactive")
                        .foregroundStyle(currentSession.active ? Color.green : Color.secondary)
                }
                LabeledContent("Updated") {
                    Text(Date(timeIntervalSince1970: currentSession.updatedAt), style: .relative)
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
                if viewModel.isDeleting(sessionID: session.id) || viewModel.isRenaming(sessionID: session.id) {
                    ProgressView()
                } else {
                    Menu {
                        Button("List Codex Sessions", systemImage: "list.bullet") {
                            showCodexThreadsSheet = true
                            Task {
                                await viewModel.loadCodexThreads(
                                    for: session.id,
                                    serverURLString: serverURLString,
                                    token: token,
                                    cwd: normalizedCWD(from: codexCwdFilterDraft)
                                )
                            }
                        }
                        Button("List Claude Sessions", systemImage: "list.bullet.rectangle") {
                            showClaudeSessionsSheet = true
                            if claudeResumeDirectoryDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                claudeResumeDirectoryDraft = claudeCwdFilterDraft
                            }
                            Task {
                                await viewModel.loadClaudeSessions(
                                    for: session.id,
                                    serverURLString: serverURLString,
                                    token: token,
                                    cwd: normalizedCWD(from: claudeCwdFilterDraft)
                                )
                            }
                        }
                        Button("Rename", systemImage: "pencil") {
                            renameDraft = currentSession.displayName ?? ""
                            showRenameSheet = true
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
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
        .sheet(isPresented: $showRenameSheet) {
            NavigationStack {
                Form {
                    Section("Session Title") {
                        TextField("Session title", text: $renameDraft)
                            .textInputAutocapitalization(.never)
                        Text("Leave empty to clear the custom title.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Rename Session")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            showRenameSheet = false
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            let nextTitle = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            showRenameSheet = false
                            Task {
                                await viewModel.setSessionTitle(
                                    sessionID: currentSession.id,
                                    title: nextTitle.isEmpty ? nil : nextTitle,
                                    serverURLString: serverURLString,
                                    token: token
                                )
                            }
                        }
                        .disabled(viewModel.isRenaming(sessionID: session.id))
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showCodexThreadsSheet) {
            NavigationStack {
                List {
                    Section("Path Filter") {
                        TextField("Optional cwd path", text: $codexCwdFilterDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Apply Filter") {
                            Task {
                                await viewModel.loadCodexThreads(
                                    for: session.id,
                                    serverURLString: serverURLString,
                                    token: token,
                                    cwd: normalizedCWD(from: codexCwdFilterDraft)
                                )
                            }
                        }
                        .disabled(viewModel.isLoadingCodexThreads)
                    }

                    if viewModel.isLoadingCodexThreads {
                        ProgressView("Loading Codex sessions…")
                    } else if let error = viewModel.selectedCodexThreadsErrorMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Unable to load Codex sessions")
                                .font(.headline)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Retry") {
                                Task {
                                    await viewModel.loadCodexThreads(
                                        for: session.id,
                                        serverURLString: serverURLString,
                                        token: token,
                                        cwd: normalizedCWD(from: codexCwdFilterDraft)
                                    )
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    } else if viewModel.selectedCodexThreads.isEmpty {
                        Text("No existing Codex sessions")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.selectedCodexThreads) { thread in
                            CodexThreadRow(thread: thread)
                        }
                    }
                }
                .navigationTitle("Codex Sessions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            showCodexThreadsSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showClaudeSessionsSheet) {
            NavigationStack {
                List {
                    Section("Path Filter") {
                        TextField("Optional cwd path", text: $claudeCwdFilterDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Apply Filter") {
                            Task {
                                await viewModel.loadClaudeSessions(
                                    for: session.id,
                                    serverURLString: serverURLString,
                                    token: token,
                                    cwd: normalizedCWD(from: claudeCwdFilterDraft)
                                )
                            }
                        }
                        .disabled(viewModel.isLoadingClaudeSessions)
                    }
                    Section("Resume") {
                        TextField("Directory for resumed session", text: $claudeResumeDirectoryDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text("If empty, selected row cwd is used.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let status = viewModel.claudeResumeStatusMessage {
                            Text(status)
                                .font(.footnote)
                                .foregroundStyle(.green)
                        }
                        if let error = viewModel.claudeResumeErrorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }

                    if viewModel.isLoadingClaudeSessions {
                        ProgressView("Loading Claude sessions…")
                    } else if let error = viewModel.selectedClaudeSessionsErrorMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Unable to load Claude sessions")
                                .font(.headline)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Retry") {
                                Task {
                                    await viewModel.loadClaudeSessions(
                                        for: session.id,
                                        serverURLString: serverURLString,
                                        token: token,
                                        cwd: normalizedCWD(from: claudeCwdFilterDraft)
                                    )
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    } else if viewModel.selectedClaudeSessions.isEmpty {
                        Text("No existing Claude sessions")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.selectedClaudeSessions) { row in
                            Button {
                                let resumeDirectory =
                                    normalizedCWD(from: claudeResumeDirectoryDraft)
                                    ?? normalizedCWD(from: row.cwd ?? "")
                                    ?? normalizedCWD(from: claudeCwdFilterDraft)
                                    ?? ""
                                Task {
                                    await viewModel.resumeClaudeSession(
                                        from: session.id,
                                        claudeResumeSessionID: row.id,
                                        serverURLString: serverURLString,
                                        token: token,
                                        directory: resumeDirectory
                                    )
                                }
                            } label: {
                                ClaudeSessionRow(
                                    session: row,
                                    isResuming: viewModel.claudeResumeInProgressSessionID == row.id
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(
                                viewModel.isResumingClaudeSession &&
                                    viewModel.claudeResumeInProgressSessionID != row.id
                            )
                        }
                    }
                }
                .navigationTitle("Claude Sessions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            showClaudeSessionsSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .alert(
            "Delete session?",
            isPresented: $showDeleteConfirmation,
            actions: {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.deleteSession(
                            sessionID: currentSession.id,
                            serverURLString: serverURLString,
                            token: token
                        )
                        if !viewModel.sessions.contains(where: { $0.id == currentSession.id }) {
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

    private var currentSession: APISession {
        viewModel.sessions.first(where: { $0.id == session.id }) ?? session
    }

    private func normalizedCWD(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct CodexThreadRow: View {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let fallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    let thread: APICodexThreadSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(threadName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(thread.id)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let dateText {
                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var threadName: String {
        let trimmed = thread.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return "Untitled"
    }

    private var dateText: String? {
        let candidate = thread.updatedAt ?? thread.createdAt
        guard let candidate else { return nil }
        guard let date = Self.formatter.date(from: candidate) ?? Self.fallbackFormatter.date(from: candidate) else {
            return candidate
        }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }
}

private struct ClaudeSessionRow: View {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let fallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    let session: APIClaudeSessionSummary
    let isResuming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(session.id)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                Spacer()
                if isResuming {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Resume")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
            if let cwd = session.cwd, !cwd.isEmpty {
                Text(cwd)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let dateText {
                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var dateText: String? {
        let candidate = session.updatedAt ?? session.createdAt
        guard let candidate else { return nil }
        guard let date = Self.formatter.date(from: candidate) ?? Self.fallbackFormatter.date(from: candidate) else {
            return candidate
        }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
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
