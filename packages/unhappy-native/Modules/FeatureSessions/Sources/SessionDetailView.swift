import SwiftUI
import CoreKit
import FeatureSessionTools

@MainActor
public struct SessionDetailView: View {
    private enum SessionQuickTool: String, Identifiable {
        case info
        case files
        case review
        case worktree

        var id: String { rawValue }
    }

    let session: APISession
    @ObservedObject var viewModel: SessionsViewModel
    let serverURLString: String
    let token: String
    let makeSessionToolsViewModel: @MainActor () -> SessionToolsViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var showRenameSheet = false
    @State private var showCodexThreadsSheet = false
    @State private var showClaudeSessionsSheet = false
    @State private var renameDraft = ""
    @State private var codexCwdFilterDraft = ""
    @State private var codexResumeDirectoryDraft = ""
    @State private var claudeCwdFilterDraft = ""
    @State private var claudeResumeDirectoryDraft = ""
    @State private var draftMessage = ""
    @State private var steerMode: APISessionSteerMode = .queue
    @State private var presentedQuickTool: SessionQuickTool?

    public init(
        session: APISession,
        viewModel: SessionsViewModel,
        serverURLString: String,
        token: String,
        makeSessionToolsViewModel: @escaping @MainActor () -> SessionToolsViewModel
    ) {
        self.session = session
        self.viewModel = viewModel
        self.serverURLString = serverURLString
        self.token = token
        self.makeSessionToolsViewModel = makeSessionToolsViewModel
    }

    public var body: some View {
        List {
            Section("Session") {
                LabeledContent("Title") {
                    Text(currentSessionTitle)
                        .foregroundStyle(currentSessionHasDisplayTitle ? .primary : .secondary)
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
                    Text("No synced messages yet for this session")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.selectedSessionMessages) { message in
                        NavigationLink {
                            SessionMessageDetailView(
                                presentation: SessionMessageDetailPresentationBuilder.make(from: message)
                            )
                        } label: {
                            SessionMessageRow(message: message)
                        }
                    }
                }
            }

        }
        .listStyle(.plain)
        .safeAreaInset(edge: .bottom) {
            bottomDock
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
                            if codexResumeDirectoryDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                codexResumeDirectoryDraft = codexCwdFilterDraft
                            }
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
        .onAppear {
            viewModel.startSelectedSessionMessagesPolling(
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
            viewModel.stopSelectedSessionMessagesPolling()
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
        .sheet(item: $presentedQuickTool) { tool in
            NavigationStack {
                quickToolDestinationView(tool)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { presentedQuickTool = nil }
                        }
                    }
            }
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
                    Section("Resume") {
                        TextField("Directory for resumed session", text: $codexResumeDirectoryDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text("If empty, selected row cwd is used.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let status = viewModel.codexResumeStatusMessage {
                            Text(status)
                                .font(.footnote)
                                .foregroundStyle(.green)
                        }
                        if let error = viewModel.codexResumeErrorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
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
                            Button {
                                let resumeDirectory =
                                    normalizedCWD(from: codexResumeDirectoryDraft)
                                    ?? normalizedCWD(from: thread.cwd ?? "")
                                    ?? normalizedCWD(from: codexCwdFilterDraft)
                                    ?? ""
                                Task {
                                    await viewModel.resumeCodexThread(
                                        from: session.id,
                                        codexResumeThreadID: thread.id,
                                        serverURLString: serverURLString,
                                        token: token,
                                        directory: resumeDirectory
                                    )
                                }
                            } label: {
                                CodexThreadRow(
                                    thread: thread,
                                    isResuming: viewModel.codexResumeInProgressThreadID == thread.id
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(
                                viewModel.isResumingCodexSession &&
                                    viewModel.codexResumeInProgressThreadID != thread.id
                            )
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
                Text("This first tries to terminate the local session process, then permanently deletes the session record from the server. Project files and directories are not deleted.")
            }
        )
    }

    private var currentSession: APISession {
        viewModel.sessions.first(where: { $0.id == session.id }) ?? session
    }

    private var currentSessionDisplayTitle: String? {
        guard let raw = currentSession.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              raw != currentSession.id else {
            return nil
        }
        return raw
    }

    private var currentSessionHasDisplayTitle: Bool {
        currentSessionDisplayTitle != nil
    }

    private var currentSessionTitle: String {
        if let currentSessionDisplayTitle {
            return currentSessionDisplayTitle
        }
        if let seq = currentSession.seq, seq > 0 {
            return "Session #\(seq)"
        }
        return "Session"
    }

    private var bottomDock: some View {
        VStack(spacing: 8) {
            composerBar
            quickToolsBar
        }
        .padding(.top, 8)
        .background(.ultraThinMaterial)
    }

    private var composerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Ask for follow-up changes", text: $draftMessage, axis: .vertical)
                .lineLimit(2...6)
                .textInputAutocapitalization(.sentences)

            HStack(spacing: 10) {
                Picker("Send Mode", selection: $steerMode) {
                    Text("Queue").tag(APISessionSteerMode.queue)
                    Text("Steer").tag(APISessionSteerMode.immediate)
                }
                .pickerStyle(.segmented)

                Button(viewModel.isSendingMessage(sessionID: session.id) ? "Sending…" : "Send") {
                    let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    Task {
                        let sent = await viewModel.sendMessage(
                            for: session.id,
                            text: text,
                            steerMode: steerMode,
                            serverURLString: serverURLString,
                            token: token
                        )
                        if sent {
                            draftMessage = ""
                            if steerMode == .immediate {
                                steerMode = .queue
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    viewModel.isSendingMessage(sessionID: session.id) ||
                    draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            if let status = viewModel.sendMessageStatusMessage {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
            if let error = viewModel.sendMessageErrorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 12)
    }

    private var quickToolsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quickToolButton(
                    title: "Info",
                    systemImage: "info.circle",
                    tool: .info
                )
                quickToolButton(
                    title: "Files",
                    systemImage: "doc.text",
                    tool: .files
                )
                quickToolButton(
                    title: "Diff",
                    systemImage: "doc.text.magnifyingglass",
                    tool: .review
                )
                quickToolButton(
                    title: "Worktree",
                    systemImage: "checkmark.circle",
                    tool: .worktree
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func quickToolButton(
        title: String,
        systemImage: String,
        tool: SessionQuickTool
    ) -> some View {
        Button {
            presentedQuickTool = tool
        } label: {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func quickToolDestinationView(_ tool: SessionQuickTool) -> some View {
        switch tool {
        case .info:
            SessionInfoView(
                session: currentSession,
                serverURLString: serverURLString,
                token: token,
                makeViewModel: makeSessionToolsViewModel
            )
            .navigationTitle("Session Info")
            .navigationBarTitleDisplayMode(.inline)
        case .files:
            SessionFileView(
                session: currentSession,
                serverURLString: serverURLString,
                token: token,
                makeViewModel: makeSessionToolsViewModel
            )
            .navigationTitle("File Viewer")
            .navigationBarTitleDisplayMode(.inline)
        case .review:
            SessionReviewView(
                session: currentSession,
                serverURLString: serverURLString,
                token: token,
                makeViewModel: makeSessionToolsViewModel
            )
            .navigationTitle("Review Diff")
            .navigationBarTitleDisplayMode(.inline)
        case .worktree:
            SessionFinishView(
                session: currentSession,
                serverURLString: serverURLString,
                token: token,
                makeViewModel: makeSessionToolsViewModel
            )
            .navigationTitle("Finish Worktree")
            .navigationBarTitleDisplayMode(.inline)
        }
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
    let isResuming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(threadName)
                    .font(.subheadline.weight(.semibold))
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

private struct SessionMessageDetailView: View {
    let presentation: SessionMessageDetailPresentation

    var body: some View {
        List {
            Section("Overview") {
                LabeledContent("Sequence") {
                    Text(presentation.sequenceText)
                        .font(.footnote.monospaced())
                }
                LabeledContent("Message ID") {
                    Text(presentation.id)
                        .font(.footnote.monospaced())
                        .lineLimit(1)
                }
                if let localID = presentation.localID {
                    LabeledContent("Local ID") {
                        Text(localID)
                            .font(.footnote.monospaced())
                            .lineLimit(1)
                    }
                }
            }

            Section("Timestamps") {
                LabeledContent("Created") {
                    Text(presentation.createdAtText)
                }
                LabeledContent("Updated") {
                    Text(presentation.updatedAtText)
                }
            }

            Section("Content") {
                if let contentType = presentation.contentType {
                    LabeledContent("Type") {
                        Text(contentType)
                            .font(.footnote.monospaced())
                    }
                    LabeledContent("Payload Size") {
                        Text("\(presentation.payloadCharacterCount) chars")
                            .font(.footnote.monospaced())
                    }
                    if let payloadPreview = presentation.payloadPreview {
                        Text(payloadPreview)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(nil)
                    }
                    if presentation.payloadTruncated {
                        Text("Payload preview is truncated to first \(SessionMessageDetailPresentationBuilder.payloadPreviewLimit) chars.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !presentation.payloadFields.isEmpty {
                        Divider()
                        Text("Parsed Fields")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(presentation.payloadFields) { field in
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
                } else {
                    Text("No content payload")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Message")
        .navigationBarTitleDisplayMode(.inline)
    }
}
