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

    private enum SessionComposerFlavor: String {
        case codex
        case claude
        case gemini
    }

    private enum SessionComposerFocusField: Hashable {
        case message
        case customModel
    }

    private struct CachedTranscriptPresentation: Equatable {
        let sourceMessage: APISessionMessage
        let dataEncryptionKey: String?
        let presentation: SessionTranscriptMessagePresentation
    }

    private struct PendingPermissionRequest: Identifiable, Equatable {
        let id: String
        let callID: String
        let toolName: String
        let summary: String?
    }

    private static let customModelOverrideOption = "__custom_model_override__"
    private static let modelPickerDefaultOption = "__model_default__"
    private static let modelPickerCustomOption = "__model_custom__"
    private static let modelPickerPresetPrefix = "__model_preset__:"
    private static let effortPickerPresetPrefix = "__effort_preset__:"
    private static let permissionModePickerDefaultOption = "__permission_mode_default__"
    private static let permissionModePickerPresetPrefix = "__permission_mode_preset__:"
    private static let transcriptBottomAnchorID = "__session_transcript_bottom__"
    private static let quickToolsFadeWidth: CGFloat = 16
    private static let quickToolsBarHeight: CGFloat = 36

    private enum SessionComposerEffortSelection: String, CaseIterable, Identifiable {
        case auto
        case low
        case medium
        case high
        case max
        case xhigh

        var id: String { rawValue }

        var label: String {
            switch self {
            case .auto:
                return "Auto"
            case .low:
                return "Low"
            case .medium:
                return "Medium"
            case .high:
                return "High"
            case .max:
                return "Max"
            case .xhigh:
                return "XHigh"
            }
        }

        var overrideValue: SessionMessageEffortOverride {
            switch self {
            case .auto:
                return .auto
            case .low:
                return .low
            case .medium:
                return .medium
            case .high:
                return .high
            case .max:
                return .max
            case .xhigh:
                return .xhigh
            }
        }
    }

    let session: APISession
    @ObservedObject var viewModel: SessionsViewModel
    let serverURLString: String
    let token: String
    let makeSessionToolsViewModel: @MainActor () -> SessionToolsViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("unhappy.native.showReasoningDetails")
    private var showReasoningDetails = false
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
    @State private var presentedQuickTool: SessionQuickTool?
    @State private var applyModelOverride = false
    @State private var modelOverrideDraft = ""
    @State private var selectedModelOverrideOption = ""
    @State private var applyEffortOverride = false
    @State private var selectedEffortOverride: SessionComposerEffortSelection = .auto
    @State private var selectedPermissionModeOverride: APISessionMessagePermissionMode?
    @State private var serverModelOverrideOptions: [String] = []
    @State private var shouldFollowTranscript = true
    @State private var scrollToBottomRequestID = UUID()
    @State private var transcriptPresentationCache: [String: CachedTranscriptPresentation] = [:]
    @State private var cachedVisibleTranscriptPresentations: [SessionTranscriptMessagePresentation] = []
    @State private var transcriptSubAgentInProgressCount = 0
    @State private var respondingPermissionRequestID: String?
    @State private var isRecoveringDisconnectedSession = false
    @State private var permissionActionStatusMessage: String?
    @State private var permissionActionErrorMessage: String?
    @GestureState private var isInteractingWithBottomDock = false
    @FocusState private var focusedComposerField: SessionComposerFocusField?

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
        ScrollViewReader { scrollProxy in
            let messagesSectionRows = MessagesSectionRows(
                isLoading: viewModel.isLoadingSessionMessages,
                errorMessage: viewModel.selectedSessionErrorMessage,
                visibleTranscriptPresentations: visibleTranscriptPresentations,
                liveStatusText: liveStatusText,
                transcriptBottomAnchorID: Self.transcriptBottomAnchorID,
                onReferenceToggle: {
                    shouldFollowTranscript = false
                },
                onRetry: {
                    Task {
                        await viewModel.loadMessages(
                            for: session.id,
                            serverURLString: serverURLString,
                            token: token
                        )
                    }
                }
            )
            List {
                Section {
                    sessionSectionContent
                }

                Section {
                    messagesSectionRows
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(transcriptBackground)
            .scrollDismissesKeyboard(.immediately)
            .scrollDisabled(isInteractingWithBottomDock)
            .simultaneousGesture(
                TapGesture().onEnded {
                    focusedComposerField = nil
                }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 8).onChanged { value in
                    // Only treat mostly-vertical drags as transcript scrolling.
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    focusedComposerField = nil
                    guard shouldFollowTranscript else { return }
                    shouldFollowTranscript = false
                }
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomInsetContent
            }
            .defaultScrollAnchor(.bottom)
            .toolbar(.hidden, for: .tabBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    topBarTitleView
                }
                ToolbarItem(placement: .topBarTrailing) {
                    toolbarTrailingContent
                }
            }
            .onAppear {
                if !availableEffortSelections.contains(selectedEffortOverride),
                   let first = availableEffortSelections.first {
                    selectedEffortOverride = first
                }
                if serverModelOverrideOptions.isEmpty {
                    Task {
                        await loadServerModelOptions()
                    }
                }
                viewModel.startSelectedSessionMessagesPolling(
                    for: session.id,
                    serverURLString: serverURLString,
                    token: token
                )
                refreshTranscriptPresentationCacheForCurrentState()
                scrollTranscriptToBottom(using: scrollProxy, animated: false)
            }
            .onChange(of: viewModel.selectedSessionMessages) { _, messages in
                refreshTranscriptPresentationCache(
                    messages: messages,
                    dataEncryptionKey: currentSession.dataEncryptionKey
                )
            }
            .onChange(of: currentSession.dataEncryptionKey) { _, _ in
                refreshTranscriptPresentationCacheForCurrentState()
            }
            .onChange(of: visibleTranscriptMessageIDs) { oldIDs, newIDs in
                handleVisibleTranscriptMessageIDsChange(
                    oldIDs: oldIDs,
                    newIDs: newIDs,
                    using: scrollProxy
                )
            }
            .onChange(of: scrollToBottomRequestID) { _, _ in
                scrollTranscriptToBottom(using: scrollProxy)
            }
            .onChange(of: focusedComposerField) { _, focusedField in
                guard focusedField != nil else { return }
                shouldFollowTranscript = true
                scrollTranscriptToBottom(using: scrollProxy)
            }
            .onChange(of: viewModel.isLoadingSessionMessages) { wasLoading, isLoading in
                guard wasLoading && !isLoading else { return }
                shouldFollowTranscript = true
                scrollTranscriptToBottom(using: scrollProxy, animated: false)
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
            }
            )
        }
    }

    private var currentSession: APISession {
        viewModel.sessions.first(where: { $0.id == session.id }) ?? session
    }

    private var currentSessionDisplayTitle: String? {
        SessionDisplayTitleResolver.resolvedDisplayTitle(for: currentSession)
    }

    private var currentSessionHasDisplayTitle: Bool {
        currentSessionDisplayTitle != nil
    }

    private var currentSessionTitle: String {
        if let currentSessionDisplayTitle {
            return currentSessionDisplayTitle
        }
        return SessionDisplayTitleResolver.fallbackTitle(for: currentSession)
    }

    private var subAgentInProgressCount: Int {
        guard currentSession.active else { return 0 }
        return max(transcriptSubAgentInProgressCount, collabInProgressCountFromAgentState)
    }

    private var pendingPermissionRequests: [PendingPermissionRequest] {
        let sources = [decodedSessionAgentState, decodedSessionMetadata]
        let requestMap = SessionPayloadValueResolver.firstDictionary(
            in: sources,
            keys: [
                "requests",
                "pendingRequests",
                "approvalRequestMap",
                "permissionRequestMap",
            ]
        ) ?? [:]

        var rows: [PendingPermissionRequest] = []
        rows.reserveCapacity(requestMap.count)
        for (rawRequestID, rawValue) in requestMap {
            let requestID = rawRequestID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !requestID.isEmpty else { continue }
            guard let requestPayload = rawValue as? [String: Any] else {
                rows.append(
                    PendingPermissionRequest(
                        id: requestID,
                        callID: requestID,
                        toolName: "Tool",
                        summary: nil
                    )
                )
                continue
            }

            let callID = SessionPayloadValueResolver.firstString(
                in: [requestPayload],
                keys: ["callId", "toolCallId", "id"]
            ) ?? requestID
            let toolName = SessionPayloadValueResolver.firstString(
                in: [requestPayload],
                keys: ["toolName", "tool", "name"]
            ) ?? "Tool"
            let summary = permissionSummary(from: requestPayload)
            rows.append(
                PendingPermissionRequest(
                    id: requestID,
                    callID: callID,
                    toolName: toolName,
                    summary: summary
                )
            )
        }

        return rows.sorted { lhs, rhs in
            lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
    }

    private var resumeDirectoryForDisconnectedSession: String? {
        let raw = SessionPayloadValueResolver.firstString(
            in: [decodedSessionAgentState, decodedSessionMetadata],
            keys: [
                "cwd",
                "path",
                "directory",
                "workingDirectory",
                "workDir",
                "projectPath",
            ]
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else {
            return nil
        }
        return raw
    }

    private var upstreamAgentSessionIDForResume: String? {
        let raw = SessionPayloadValueResolver.firstString(
            in: [decodedSessionAgentState, decodedSessionMetadata],
            keys: [
                "agentSessionId",
                "agent_session_id",
                "upstreamSessionId",
                "upstream_session_id",
            ]
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else {
            return nil
        }
        return raw
    }

    private var canAutoResumeDisconnectedSession: Bool {
        guard parsedSessionAgent != nil else { return false }
        guard resumeDirectoryForDisconnectedSession != nil else { return false }
        if parsedSessionAgent == .codex || parsedSessionAgent == .claude {
            return upstreamAgentSessionIDForResume != nil
        }
        return true
    }

    private func permissionSummary(from requestPayload: [String: Any]) -> String? {
        if let summary = SessionPayloadValueResolver.firstString(
            in: [requestPayload],
            keys: ["reason", "message", "description", "prompt"]
        ) {
            let normalized = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                return clippedSummary(normalized)
            }
        }

        if let input = SessionPayloadValueResolver.firstDictionary(
            in: [requestPayload],
            keys: ["input", "arguments", "args", "payload"]
        ) {
            if let command = SessionPayloadValueResolver.firstString(
                in: [input],
                keys: ["cmd", "command", "query", "q", "url", "path"]
            ) {
                return clippedSummary(command)
            }
            if JSONSerialization.isValidJSONObject(input),
               let data = try? JSONSerialization.data(withJSONObject: input, options: []),
               let text = String(data: data, encoding: .utf8) {
                return clippedSummary(text)
            }
        }

        return nil
    }

    private func clippedSummary(_ raw: String, limit: Int = 180) -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)) + "…"
    }

    private func respondToPermissionRequest(
        _ requestID: String,
        approved: Bool
    ) {
        guard respondingPermissionRequestID == nil else { return }
        let normalizedRequestID = requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRequestID.isEmpty else { return }

        respondingPermissionRequestID = normalizedRequestID
        permissionActionStatusMessage = nil
        permissionActionErrorMessage = nil

        let currentSessionID = currentSession.id
        Task {
            let toolsViewModel = makeSessionToolsViewModel()
            toolsViewModel.permissionRequestID = normalizedRequestID
            toolsViewModel.permissionDecision = approved ? .approvedForSession : .denied
            toolsViewModel.permissionMode = .default
            toolsViewModel.permissionAllowTools = ""
            await toolsViewModel.submitPermissionDecision(
                sessionID: currentSessionID,
                serverURLString: serverURLString,
                token: token
            )

            let actionError = toolsViewModel.permissionErrorMessage?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let actionError, !actionError.isEmpty {
                respondingPermissionRequestID = nil
                permissionActionStatusMessage = nil
                if actionError.lowercased().contains("session rpc is not connected") {
                    if canAutoResumeDisconnectedSession {
                        isRecoveringDisconnectedSession = true
                        let resumedSessionID = await recoverDisconnectedSessionForApproval()
                        isRecoveringDisconnectedSession = false
                        if let resumedSessionID, !resumedSessionID.isEmpty {
                            permissionActionErrorMessage = nil
                            permissionActionStatusMessage =
                                "Session resumed into \(resumedSessionID). Open it and retry approval."
                        } else {
                            permissionActionErrorMessage =
                                "Session is disconnected. Failed to auto-resume. Resume it manually, then retry approval."
                        }
                    } else {
                        permissionActionErrorMessage =
                            "Session is disconnected. Resume or reopen this session, then try approval again."
                    }
                } else {
                    permissionActionErrorMessage = actionError
                }
                return
            }

            respondingPermissionRequestID = nil
            permissionActionErrorMessage = nil
            permissionActionStatusMessage = approved ? "Approved permission request" : "Denied permission request"

            await viewModel.load(
                serverURLString: serverURLString,
                token: token
            )
            await viewModel.loadMessages(
                for: currentSessionID,
                serverURLString: serverURLString,
                token: token
            )
        }
    }

    private func recoverDisconnectedSessionForApproval() async -> String? {
        guard let agent = parsedSessionAgent else {
            return nil
        }
        guard let directory = resumeDirectoryForDisconnectedSession else {
            return nil
        }

        let upstreamSessionID = upstreamAgentSessionIDForResume
        let codexResumeThreadID = agent == .codex ? upstreamSessionID : nil
        let claudeResumeSessionID = agent == .claude ? upstreamSessionID : nil
        if agent == .codex && (codexResumeThreadID == nil || codexResumeThreadID?.isEmpty == true) {
            return nil
        }
        if agent == .claude && (claudeResumeSessionID == nil || claudeResumeSessionID?.isEmpty == true) {
            return nil
        }

        let spawnUseCase = SessionSpawnUseCase(service: URLSessionSessionsService())
        do {
            let response = try await spawnUseCase.spawnSession(
                serverURLString: serverURLString,
                token: token,
                sessionID: currentSession.id,
                directory: directory,
                agent: agent,
                codexResumeThreadID: codexResumeThreadID,
                claudeResumeSessionID: claudeResumeSessionID,
                approvedNewDirectoryCreation: true
            )
            await viewModel.load(
                serverURLString: serverURLString,
                token: token
            )
            return response.sessionID
        } catch {
            return nil
        }
    }

    @ViewBuilder
    private var sessionSectionContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.caption2)
                .foregroundStyle(AppPalette.secondaryText)
            Text("Session")
                .font(.caption2.monospaced().weight(.bold))
                .foregroundStyle(AppPalette.secondaryText)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 2, leading: 14, bottom: 2, trailing: 14))

        VStack(spacing: 0) {
            sessionSummaryPanelRow(
                title: "Title",
                value: currentSessionTitle,
                valueColor: currentSessionHasDisplayTitle ? AppPalette.primaryText : AppPalette.secondaryText
            )
            Divider().opacity(0.28)
            sessionSummaryPanelRow(
                title: "ID",
                value: currentSession.id,
                valueFont: .footnote.monospaced(),
                valueColor: AppPalette.secondaryText
            )
            Divider().opacity(0.28)
            sessionSummaryPanelRow(
                title: "Status",
                value: currentSession.active ? "Active" : "Inactive",
                valueColor: currentSession.active ? AppPalette.liveActivity : AppPalette.secondaryText
            )
            Divider().opacity(0.28)
            sessionSummaryPanelRow(
                title: "Updated",
                value: SessionTimestampPresentation.updatedLabel(for: currentSession.updatedAt),
                valueColor: AppPalette.secondaryText
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppPalette.chatToolBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppPalette.chatBubbleStroke, lineWidth: 1)
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(
            EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)
        )

    }

    private var approvalBottomSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                Text("Approval Required")
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(AppPalette.secondaryText)
                    .textCase(.uppercase)
            }

            ForEach(pendingPermissionRequests) { request in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(request.toolName)
                            .font(.subheadline.monospaced().weight(.semibold))
                            .foregroundStyle(AppPalette.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Text(request.callID)
                            .font(.caption2.monospaced())
                            .foregroundStyle(AppPalette.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if let summary = request.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppPalette.secondaryText)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        let isResponding = respondingPermissionRequestID == request.id
                        Button {
                            respondToPermissionRequest(request.id, approved: true)
                        } label: {
                            if isResponding {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Approve")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(respondingPermissionRequestID != nil || isRecoveringDisconnectedSession)

                        Button(role: .destructive) {
                            respondToPermissionRequest(request.id, approved: false)
                        } label: {
                            Text("Deny")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .disabled(respondingPermissionRequestID != nil || isRecoveringDisconnectedSession)
                    }
                }

                if request.id != pendingPermissionRequests.last?.id {
                    Divider().opacity(0.22)
                }
            }

            if let status = permissionActionStatusMessage, !status.isEmpty {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
            if isRecoveringDisconnectedSession {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Recovering disconnected session…")
                        .font(.footnote)
                        .foregroundStyle(AppPalette.secondaryText)
                }
            }
            if let error = permissionActionErrorMessage, !error.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(bottomSheetSurfaceColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.45), lineWidth: 1)
        )
        .shadow(
            color: AppPalette.chromeShadow.opacity(colorScheme == .dark ? 0.36 : 0.10),
            radius: 8,
            y: 2
        )
    }

    private func sessionSummaryPanelRow(
        title: String,
        value: String,
        valueFont: Font = .subheadline.monospaced().weight(.semibold),
        valueColor: Color = AppPalette.primaryText
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(AppPalette.secondaryText)
            Spacer(minLength: 0)
            Text(value)
                .font(valueFont)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var transcriptBackground: some View {
        ZStack {
            LinearGradient(
                colors: backgroundGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(AppPalette.accent.opacity(colorScheme == .dark ? 0.06 : 0.07))
                .frame(width: 320, height: 320)
                .blur(radius: 56)
                .offset(x: 160, y: -260)
        }
        .ignoresSafeArea()
    }

    private var backgroundGradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.08, green: 0.10, blue: 0.14),
                Color(red: 0.06, green: 0.07, blue: 0.10),
            ]
        }

        return [
            AppPalette.chatBackgroundTop,
            AppPalette.chatBackgroundBottom,
        ]
    }

    private var isKeyboardActive: Bool {
        focusedComposerField != nil
    }

    private var bottomSheetSurfaceColor: Color {
        Color(.systemBackground)
    }

    private var bottomSheetCornerRadius: CGFloat {
        22
    }

    private var bottomDock: some View {
        VStack(spacing: isKeyboardActive ? 6 : 10) {
            composerBar
            quickToolsBar
        }
        .padding(.horizontal, 12)
        .padding(.top, isKeyboardActive ? 8 : 10)
        .padding(.bottom, isKeyboardActive ? 4 : 8)
        .background(
            RoundedRectangle(cornerRadius: bottomSheetCornerRadius, style: .continuous)
                .fill(bottomSheetSurfaceColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: bottomSheetCornerRadius, style: .continuous)
                .stroke(
                    AppPalette.chromeSurfaceStroke.opacity(isKeyboardActive ? 0.32 : 0.55),
                    lineWidth: 1
                )
        )
        .shadow(
            color: AppPalette.chromeShadow.opacity(colorScheme == .dark ? 0.42 : 0.14),
            radius: isKeyboardActive ? 8 : 10,
            y: isKeyboardActive ? 2 : 3
        )
        .animation(.easeInOut(duration: 0.18), value: isKeyboardActive)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).updating($isInteractingWithBottomDock) { _, state, _ in
                state = true
            }
        )
    }

    private var bottomInsetContent: some View {
        VStack(spacing: isKeyboardActive ? 6 : 8) {
            if subAgentInProgressCount > 0 {
                subAgentLiveBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if !pendingPermissionRequests.isEmpty {
                approvalBottomSheet
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            bottomDock
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.bottom, isKeyboardActive ? 6 : 8)
        .animation(.easeInOut(duration: 0.2), value: subAgentInProgressCount > 0)
        .animation(.easeInOut(duration: 0.2), value: pendingPermissionRequests.count)
        .animation(.easeInOut(duration: 0.18), value: isKeyboardActive)
    }

    private var topBarTitleView: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppPalette.secondaryText)
            Text(currentSessionTitle)
                .font(.subheadline.monospaced().weight(.semibold))
                .foregroundStyle(AppPalette.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    private var toolbarTrailingContent: some View {
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
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppPalette.secondaryText)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(PressableScaleButtonStyle())
        }
    }

    private var subAgentLiveBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.2.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppPalette.liveActivity)
            Text("\(subAgentInProgressCount)개 진행중")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppPalette.liveActivity)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppPalette.liveActivityMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppPalette.liveActivity.opacity(0.4), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .shadow(color: AppPalette.liveActivity.opacity(0.2), radius: 6, y: 2)
    }

    private var composerBar: some View {
        VStack(alignment: .leading, spacing: isKeyboardActive ? 8 : 10) {
            let isSending = viewModel.isSendingMessage(sessionID: session.id)
            let queuedComposerMessages = viewModel.queuedComposerMessages(for: currentSession.id)

            if !queuedComposerMessages.isEmpty {
                VStack(alignment: .leading, spacing: isKeyboardActive ? 6 : 8) {
                    let visibleQueuedMessages = Array(queuedComposerMessages.suffix(3))
                    let hiddenCount = max(0, queuedComposerMessages.count - visibleQueuedMessages.count)
                    let visibleStartIndex = max(0, queuedComposerMessages.count - visibleQueuedMessages.count)

                    HStack(spacing: 6) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.caption2)
                            .foregroundStyle(AppPalette.secondaryText)
                        Text("Steer Stack")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppPalette.secondaryText)
                        if hiddenCount > 0 {
                            Text("+\(hiddenCount)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(AppPalette.secondaryText)
                        }
                        Spacer(minLength: 0)
                        Text(queuedComposerMessages.count == 1 ? "1 queued" : "\(queuedComposerMessages.count) queued")
                            .font(.caption2.monospaced())
                            .foregroundStyle(AppPalette.secondaryText)
                    }

                    if !isKeyboardActive {
                        ForEach(Array(visibleQueuedMessages.enumerated()), id: \.offset) { index, text in
                            let queueIndex = visibleStartIndex + index
                            HStack(spacing: 8) {
                                Image(systemName: "clock")
                                    .font(.caption2)
                                    .foregroundStyle(AppPalette.secondaryText)
                                Text(text)
                                    .font(.footnote)
                                    .lineLimit(1)
                                    .foregroundStyle(AppPalette.primaryText)
                                Spacer(minLength: 0)
                                Button("Edit") {
                                    let restored = viewModel.takeQueuedComposerMessage(
                                        for: currentSession.id,
                                        at: queueIndex
                                    ) ?? text
                                    draftMessage = restored
                                    focusedComposerField = .message
                                }
                                .buttonStyle(.borderless)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                            }

                            if index < visibleQueuedMessages.count - 1 {
                                Rectangle()
                                    .fill(AppPalette.chromeDivider.opacity(0.7))
                                    .frame(height: 1)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppPalette.controlSurface.opacity(colorScheme == .dark ? 0.72 : 0.9))
                )
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.accent)
                    .frame(width: 18, height: 18)
                    .padding(.top, 2)

                TextField("Ask for follow-up changes", text: $draftMessage, axis: .vertical)
                    .lineLimit(isKeyboardActive ? 1...3 : 1...4)
                    .textInputAutocapitalization(.sentences)
                    .font(.subheadline.weight(.medium))
                    .focused($focusedComposerField, equals: .message)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, isKeyboardActive ? 9 : 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppPalette.composerFieldBackground)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        focusedComposerField == .message
                            ? AppPalette.accent.opacity(0.55)
                            : AppPalette.composerFieldStroke.opacity(0.4),
                        lineWidth: focusedComposerField == .message ? 1.5 : 1
                    )
            }

            HStack(spacing: 8) {
                Button {
                    submitDraftMessage(with: .queue)
                } label: {
                    Label("Queue", systemImage: "clock")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppPalette.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AppPalette.controlSurface)
                        )
                }
                .buttonStyle(PressableScaleButtonStyle())
                .disabled(isSending)

                Button {
                    submitDraftMessage(with: .immediate)
                } label: {
                    Label(isSending ? "Sending…" : "Send", systemImage: "paperplane.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            AppPalette.sendGradientTop,
                                            AppPalette.sendGradientBottom,
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .shadow(color: AppPalette.accent.opacity(0.3), radius: 6, y: 2)
                }
                .buttonStyle(PressableScaleButtonStyle())
                .disabled(isSending)
            }

            if applyModelOverride && selectedModelOverrideOption == Self.customModelOverrideOption {
                TextField("Custom model id", text: $modelOverrideDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                    .focused($focusedComposerField, equals: .customModel)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppPalette.controlSurface)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                focusedComposerField == .customModel
                                    ? AppPalette.accent.opacity(0.55)
                                    : AppPalette.composerFieldStroke.opacity(0.4),
                                lineWidth: focusedComposerField == .customModel ? 1.5 : 1
                            )
                    }
            }

            if let error = viewModel.sendMessageErrorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func submitDraftMessage(with steerMode: APISessionSteerMode) {
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        focusedComposerField = nil

        let modelOverride: SessionMessageModelOverride
        if applyModelOverride {
            switch selectedModelOverrideOption {
            case Self.customModelOverrideOption:
                let normalized = modelOverrideDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                modelOverride = normalized.isEmpty ? .reset : .set(normalized)
            case "":
                modelOverride = .reset
            default:
                modelOverride = .set(selectedModelOverrideOption)
            }
        } else {
            modelOverride = .inherit
        }

        let effortOverride: SessionMessageEffortOverride
        if applyEffortOverride && supportsReasoningEffortOverride {
            effortOverride = selectedEffortOverride.overrideValue
        } else {
            effortOverride = .inherit
        }

        Task {
            let sent = await viewModel.sendMessage(
                for: session.id,
                text: text,
                steerMode: steerMode,
                permissionMode: selectedPermissionModeOverride,
                modelOverride: modelOverride,
                effortOverride: effortOverride,
                serverURLString: serverURLString,
                token: token
            )
            if sent {
                shouldFollowTranscript = true
                scrollToBottomRequestID = UUID()
                draftMessage = ""
            }
        }
    }

    private var supportsReasoningEffortOverride: Bool {
        guard let flavor = parsedSessionFlavor else { return false }
        switch flavor {
        case .codex, .claude:
            return true
        case .gemini:
            return false
        }
    }

    private var availableEffortSelections: [SessionComposerEffortSelection] {
        guard let flavor = parsedSessionFlavor else {
            return [.auto, .low, .medium, .high]
        }
        switch flavor {
        case .codex:
            return [.auto, .low, .medium, .high, .xhigh]
        case .claude:
            return [.auto, .low, .medium, .high, .max]
        case .gemini:
            return [.auto]
        }
    }

    private var availableModelOverrideOptions: [String] {
        if !serverModelOverrideOptions.isEmpty {
            return serverModelOverrideOptions
        }
        guard let flavor = parsedSessionFlavor else { return [] }
        switch flavor {
        case .codex:
            return [
                "gpt-5.3-codex",
                "gpt-5.2-codex",
                "gpt-5-codex",
                "gpt-5",
            ]
        case .claude:
            return [
                "claude-opus-4-6",
                "claude-sonnet-4-5",
                "claude-haiku-4-5",
            ]
        case .gemini:
            return [
                "gemini-2.5-pro",
                "gemini-2.5-flash",
                "gemini-2.5-flash-lite",
            ]
        }
    }

    private var quickToolsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                modelMenuButton

                if supportsReasoningEffortOverride {
                    effortMenuButton
                }

                fileModeMenuButton

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
            .padding(.horizontal, Self.quickToolsFadeWidth)
            .padding(.vertical, 4)
        }
        .defaultScrollAnchor(.leading)
        .id("\(session.id)-\(supportsReasoningEffortOverride)-\(serverModelOverrideOptions.count)")
        .frame(height: Self.quickToolsBarHeight)
        .overlay(alignment: .leading) {
            LinearGradient(
                colors: [bottomSheetSurfaceColor, bottomSheetSurfaceColor.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: Self.quickToolsFadeWidth)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [bottomSheetSurfaceColor.opacity(0), bottomSheetSurfaceColor],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: Self.quickToolsFadeWidth)
            .allowsHitTesting(false)
        }
    }

    private func quickToolButton(
        title: String,
        systemImage: String,
        tool: SessionQuickTool
    ) -> some View {
        dockChipButton(
            title: title,
            systemImage: systemImage
        ) {
            focusedComposerField = nil
            presentedQuickTool = tool
        }
    }

    private var modelMenuButton: some View {
        Menu {
            ForEach(modelPickerOptions, id: \.id) { option in
                Button {
                    modelPickerSelection.wrappedValue = option.id
                } label: {
                    if modelPickerSelection.wrappedValue == option.id {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            Label(selectedModelOverrideLabel, systemImage: "cpu")
                .modifier(DockChipModifier(tone: .neutral))
        }
        .tint(.primary)
    }

    private var effortMenuButton: some View {
        Menu {
            ForEach(effortPickerOptions, id: \.id) { option in
                Button {
                    effortPickerSelection.wrappedValue = option.id
                } label: {
                    if effortPickerSelection.wrappedValue == option.id {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            Label(selectedReasoningOverrideLabel, systemImage: "brain.head.profile")
                .modifier(DockChipModifier(tone: .neutral))
        }
        .tint(.primary)
    }

    private var fileModeMenuButton: some View {
        Menu {
            ForEach(permissionModePickerOptions, id: \.id) { option in
                Button {
                    permissionModePickerSelection.wrappedValue = option.id
                } label: {
                    if permissionModePickerSelection.wrappedValue == option.id {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            Label(selectedFileModeLabel, systemImage: "doc.badge.gearshape")
                .modifier(DockChipModifier(tone: .neutral))
        }
        .tint(.primary)
    }

    private func dockChipButton(
        title: String,
        systemImage: String,
        isDisabled: Bool = false,
        tone: DockChipTone = .neutral,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .modifier(DockChipModifier(tone: tone))
        }
        .buttonStyle(PressableScaleButtonStyle())
        .disabled(isDisabled)
    }

    private var selectedModelOverrideLabel: String {
        guard applyModelOverride else { return resolvedCurrentModelLabel ?? "Default" }
        switch selectedModelOverrideOption {
        case Self.customModelOverrideOption:
            let normalized = modelOverrideDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? "Custom" : normalized
        default:
            return selectedModelOverrideOption
        }
    }

    private var selectedReasoningOverrideLabel: String {
        guard applyEffortOverride else { return resolvedCurrentEffortLabel ?? "Auto" }
        return selectedEffortOverride.label
    }

    private var selectedFileModeLabel: String {
        if let selectedPermissionModeOverride {
            return permissionModeDisplayLabel(for: selectedPermissionModeOverride)
        }
        if let resolvedCurrentPermissionMode {
            return permissionModeDisplayLabel(for: resolvedCurrentPermissionMode)
        }
        return "Default"
    }

    private struct PickerOption: Identifiable {
        let id: String
        let label: String
    }

    private var modelPickerOptions: [PickerOption] {
        var options: [PickerOption] = [
            PickerOption(
                id: Self.modelPickerDefaultOption,
                label: "Use current model"
            ),
        ]
        options.append(
            contentsOf: availableModelOverrideOptions.map { model in
                PickerOption(
                    id: Self.modelPickerPresetPrefix + model,
                    label: model
                )
            }
        )
        options.append(
            PickerOption(
                id: Self.modelPickerCustomOption,
                label: "Custom model…"
            )
        )
        return options
    }

    private var effortPickerOptions: [PickerOption] {
        availableEffortSelections.map { effort in
            PickerOption(
                id: Self.effortPickerPresetPrefix + effort.rawValue,
                label: effort.label
            )
        }
    }

    private var availablePermissionModeOptions: [APISessionMessagePermissionMode] {
        guard let flavor = parsedSessionFlavor else {
            return [.default, .yolo]
        }
        switch flavor {
        case .codex:
            return [.default, .readOnly, .safeYolo, .yolo]
        case .claude, .gemini:
            return [.default, .acceptEdits, .bypassPermissions, .plan]
        }
    }

    private var permissionModePickerOptions: [PickerOption] {
        var options: [PickerOption] = [
            PickerOption(
                id: Self.permissionModePickerDefaultOption,
                label: "Use current mode"
            ),
        ]
        options.append(
            contentsOf: availablePermissionModeOptions.map { mode in
                PickerOption(
                    id: Self.permissionModePickerPresetPrefix + mode.rawValue,
                    label: permissionModeDisplayLabel(for: mode)
                )
            }
        )
        return options
    }

    private var modelPickerSelection: Binding<String> {
        Binding(
            get: {
                if !applyModelOverride {
                    return Self.modelPickerDefaultOption
                }
                if selectedModelOverrideOption == Self.customModelOverrideOption {
                    return Self.modelPickerCustomOption
                }
                return Self.modelPickerPresetPrefix + selectedModelOverrideOption
            },
            set: { value in
                switch value {
                case Self.modelPickerDefaultOption:
                    applyModelOverride = false
                    selectedModelOverrideOption = ""
                    focusedComposerField = nil
                case Self.modelPickerCustomOption:
                    applyModelOverride = true
                    selectedModelOverrideOption = Self.customModelOverrideOption
                    focusedComposerField = .customModel
                default:
                    guard value.hasPrefix(Self.modelPickerPresetPrefix) else { return }
                    let model = String(value.dropFirst(Self.modelPickerPresetPrefix.count))
                    applyModelOverride = true
                    selectedModelOverrideOption = model
                    modelOverrideDraft = model
                    focusedComposerField = nil
                }
            }
        )
    }

    private var effortPickerSelection: Binding<String> {
        Binding(
            get: {
                if applyEffortOverride {
                    return Self.effortPickerPresetPrefix + selectedEffortOverride.rawValue
                }
                return Self.effortPickerPresetPrefix + SessionComposerEffortSelection.auto.rawValue
            },
            set: { value in
                guard value.hasPrefix(Self.effortPickerPresetPrefix) else { return }
                let raw = String(value.dropFirst(Self.effortPickerPresetPrefix.count))
                guard let selected = SessionComposerEffortSelection(rawValue: raw) else { return }
                selectedEffortOverride = selected
                applyEffortOverride = selected != .auto
            }
        )
    }

    private var permissionModePickerSelection: Binding<String> {
        Binding(
            get: {
                guard let selectedPermissionModeOverride else {
                    return Self.permissionModePickerDefaultOption
                }
                return Self.permissionModePickerPresetPrefix + selectedPermissionModeOverride.rawValue
            },
            set: { value in
                if value == Self.permissionModePickerDefaultOption {
                    selectedPermissionModeOverride = nil
                    return
                }
                guard value.hasPrefix(Self.permissionModePickerPresetPrefix) else { return }
                let raw = String(value.dropFirst(Self.permissionModePickerPresetPrefix.count))
                selectedPermissionModeOverride = APISessionMessagePermissionMode(rawValue: raw)
            }
        )
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

    private func scrollTranscriptToBottom(
        using proxy: ScrollViewProxy,
        animated: Bool = true
    ) {
        // Schedule on the next runloop to let List reconcile its backing collection view first.
        DispatchQueue.main.async {
            let action = {
                proxy.scrollTo(Self.transcriptBottomAnchorID, anchor: .bottom)
            }
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    action()
                }
            } else {
                action()
            }
        }
    }

    private func handleVisibleTranscriptMessageIDsChange(
        oldIDs: [String],
        newIDs: [String],
        using proxy: ScrollViewProxy
    ) {
        guard shouldFollowTranscript else { return }
        // Avoid List/UICollectionView out-of-bounds assertions during shrink updates.
        guard newIDs.count >= oldIDs.count else { return }
        scrollTranscriptToBottom(using: proxy)
    }

    private var parsedSessionFlavor: SessionComposerFlavor? {
        guard let raw = SessionPayloadValueResolver.firstString(
            in: [decodedSessionMetadata, decodedSessionAgentState],
            keys: ["flavor", "agent", "provider"]
        ) else {
            return nil
        }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let flavor = SessionComposerFlavor(rawValue: normalized) {
            return flavor
        }
        if normalized.contains("claude") {
            return .claude
        }
        if normalized.contains("gemini") {
            return .gemini
        }
        if normalized.contains("codex") || normalized.contains("openai") || normalized.contains("gpt") {
            return .codex
        }
        return nil
    }

    private var parsedSessionAgent: APISessionSpawnAgent? {
        switch parsedSessionFlavor {
        case .codex:
            return .codex
        case .claude:
            return .claude
        case .gemini:
            return .gemini
        case .none:
            return nil
        }
    }

    private var decodedSessionMetadata: [String: Any] {
        SessionPayloadValueResolver.decodeJSONObject(
            payload: currentSession.metadata,
            dataEncryptionKey: currentSession.dataEncryptionKey
        )
    }

    private var decodedSessionAgentState: [String: Any] {
        SessionPayloadValueResolver.decodeJSONObject(
            payload: currentSession.agentState,
            dataEncryptionKey: currentSession.dataEncryptionKey
        )
    }

    private var collabInProgressCountFromAgentState: Int {
        let sources = [decodedSessionAgentState, decodedSessionMetadata]
        guard let collabState = SessionPayloadValueResolver.firstDictionary(
            in: sources,
            keys: [
                "collab",
                "collaboration",
                "multiAgent",
                "multi_agent",
            ]
        ) else {
            return 0
        }

        let activeCountKeys = [
            "activeCount",
            "active_count",
            "inProgressCount",
            "in_progress_count",
            "runningCount",
            "running_count",
            "count",
        ]
        for key in activeCountKeys {
            if let activeCount = normalizedNonNegativeInt(from: collabState[key]), activeCount > 0 {
                return activeCount
            }
        }

        let state = SessionPayloadValueResolver.firstString(
            in: [collabState],
            keys: ["state", "status", "phase"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if state == "in_progress" || state == "inprogress" || state == "running" {
            return 1
        }
        return 0
    }

    private var resolvedCurrentModelLabel: String? {
        SessionPayloadValueResolver.firstString(
            in: [decodedSessionAgentState, decodedSessionMetadata],
            keys: [
                "model",
                "currentModel",
                "selectedModel",
                "modelName",
            ]
        )
    }

    private var resolvedCurrentEffortLabel: String? {
        guard let raw = SessionPayloadValueResolver.firstString(
            in: [decodedSessionAgentState, decodedSessionMetadata],
            keys: [
                "effort",
                "reasoningEffort",
                "reasoning_effort",
                "modelReasoningEffort",
            ]
        ) else {
            return nil
        }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private var resolvedCurrentPermissionMode: APISessionMessagePermissionMode? {
        guard let raw = SessionPayloadValueResolver.firstString(
            in: [decodedSessionAgentState, decodedSessionMetadata],
            keys: [
                "permissionMode",
                "permission_mode",
                "approvalMode",
                "approval_mode",
                "fileMode",
                "file_mode",
            ]
        ) else {
            return nil
        }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return APISessionMessagePermissionMode(rawValue: normalized)
    }

    private func permissionModeDisplayLabel(for mode: APISessionMessagePermissionMode) -> String {
        switch mode {
        case .default:
            return "Default"
        case .acceptEdits:
            return "Accept Edits"
        case .bypassPermissions:
            return "Bypass"
        case .plan:
            return "Plan"
        case .readOnly:
            return "Read Only"
        case .safeYolo:
            return "Safe YOLO"
        case .yolo:
            return "YOLO"
        }
    }

    private func loadServerModelOptions() async {
        let loaded = await viewModel.loadSessionModelOptions(
            for: currentSession.id,
            serverURLString: serverURLString,
            token: token,
            agent: parsedSessionAgent
        ) ?? []
        let normalized = loaded.compactMap { raw -> String? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        var deduped: [String] = []
        deduped.reserveCapacity(normalized.count)
        for model in normalized where !deduped.contains(model) {
            deduped.append(model)
        }
        if !deduped.isEmpty {
            serverModelOverrideOptions = deduped
        }
    }

    private func refreshTranscriptPresentationCache(
        messages: [APISessionMessage],
        dataEncryptionKey: String?
    ) {
        var nextCache: [String: CachedTranscriptPresentation] = [:]
        nextCache.reserveCapacity(messages.count)

        var nextPresentations: [SessionTranscriptMessagePresentation] = []
        nextPresentations.reserveCapacity(messages.count)

        for message in messages {
            if let cached = transcriptPresentationCache[message.id],
               cached.sourceMessage == message,
               cached.dataEncryptionKey == dataEncryptionKey {
                nextCache[message.id] = cached
                if !cached.presentation.entries.isEmpty {
                    nextPresentations.append(cached.presentation)
                }
                continue
            }

            let presentation = SessionTranscriptPresentationBuilder.make(
                from: message,
                dataEncryptionKey: dataEncryptionKey
            )
            let cached = CachedTranscriptPresentation(
                sourceMessage: message,
                dataEncryptionKey: dataEncryptionKey,
                presentation: presentation
            )
            nextCache[message.id] = cached
            if !presentation.entries.isEmpty {
                nextPresentations.append(presentation)
            }
        }

        let filtered = filterSubagentEntriesAndCount(in: nextPresentations)
        let mergedPresentations = coalesceStreamingEntries(in: filtered.presentations)
        let visiblePresentations = filterReasoningEntries(in: mergedPresentations)
        transcriptPresentationCache = nextCache
        if cachedVisibleTranscriptPresentations != visiblePresentations {
            cachedVisibleTranscriptPresentations = visiblePresentations
        }
        let normalizedInProgressCount = currentSession.active ? filtered.inProgressCount : 0
        if transcriptSubAgentInProgressCount != normalizedInProgressCount {
            transcriptSubAgentInProgressCount = normalizedInProgressCount
        }
    }

    private func refreshTranscriptPresentationCacheForCurrentState() {
        refreshTranscriptPresentationCache(
            messages: viewModel.selectedSessionMessages,
            dataEncryptionKey: currentSession.dataEncryptionKey
        )
    }

    private var visibleTranscriptPresentations: [SessionTranscriptMessagePresentation] {
        cachedVisibleTranscriptPresentations
    }

    private var visibleTranscriptMessageIDs: [String] {
        visibleTranscriptPresentations.map(\.messageID)
    }

    private var latestAgentThinkingEntry: SessionTranscriptEntry? {
        for presentation in visibleTranscriptPresentations.reversed() {
            for entry in presentation.entries.reversed() {
                guard entry.role == .agent else { continue }
                if entry.kind == .thinking {
                    return entry
                }
                return nil
            }
        }
        return nil
    }

    private var liveStatusText: String? {
        if viewModel.isLoadingSessionMessages {
            return "Loading messages…"
        }

        if let sendingMode = viewModel.sendingSteerMode(sessionID: currentSession.id) {
            if sendingMode == .queue {
                return "Queueing…"
            }
            return "Sending…"
        }

        let queuedCount = viewModel.queuedComposerMessages(for: currentSession.id).count
        if queuedCount > 0 {
            return queuedCount == 1 ? "Queued 1 message" : "Queued \(queuedCount) messages"
        }

        if hasPendingApprovalRequest {
            return "Approval needed"
        }

        if let latestAgentLiveStatusText {
            if shouldShowAgentLiveStatus {
                return latestAgentLiveStatusText
            }
        }

        if currentSession.active {
            return "Working…"
        }

        return nil
    }

    private var hasPendingApprovalRequest: Bool {
        let sources = [decodedSessionAgentState, decodedSessionMetadata]

        if let explicit = SessionPayloadValueResolver.firstBool(
            in: sources,
            keys: [
                "requiresUserApproval",
                "needsApproval",
                "approvalRequired",
                "approvalPending",
                "permissionPending",
                "waitingApproval",
                "awaitingApproval",
            ]
        ) {
            return explicit
        }

        if SessionPayloadValueResolver.hasNonEmptyArray(
            in: sources,
            keys: [
                "pendingPermissions",
                "approvalRequests",
                "permissionRequests",
                "pendingApprovalRequests",
            ]
        ) {
            return true
        }

        if SessionPayloadValueResolver.hasNonEmptyDictionary(
            in: sources,
            keys: [
                "requests",
                "pendingRequests",
                "approvalRequestMap",
                "permissionRequestMap",
            ]
        ) {
            return true
        }

        if let status = SessionPayloadValueResolver.firstString(
            in: sources,
            keys: ["status", "state", "phase"]
        )?.lowercased(),
           status.contains("approval") || status.contains("permission") {
            return true
        }

        return false
    }

    private var shouldShowAgentLiveStatus: Bool {
        if subAgentInProgressCount > 0 {
            return true
        }
        if latestAgentThinkingEntry != nil {
            return true
        }
        return hasOutstandingAgentToolCalls
    }

    private var latestAgentLiveStatusText: String? {
        for presentation in visibleTranscriptPresentations.reversed() {
            for entry in presentation.entries.reversed() {
                guard entry.role == .agent else { continue }
                if entry.kind == .thinking {
                    let body = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
                    return body.isEmpty ? "Thinking…" : body
                }
                if entry.kind == .text {
                    return nil
                }
                if let status = liveStatusText(from: entry) {
                    return status
                }
                return nil
            }
        }
        return nil
    }

    private func liveStatusText(from entry: SessionTranscriptEntry) -> String? {
        guard entry.kind == .toolCall || entry.kind == .raw || entry.kind == .event else {
            return nil
        }

        let title = (entry.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = title.lowercased()
        let normalizedBody = body.lowercased()
        let statusKeywords = [
            "planning",
            "explored",
            "summarizing",
            "finalizing",
            "calling",
            "crafting",
            "loading",
            "retry",
            "updating",
            "thinking",
            "image #",
        ]
        let isStatusLike = statusKeywords.contains {
            normalizedTitle.contains($0) || normalizedBody.contains($0)
        }
        guard isStatusLike else { return nil }

        if !title.isEmpty {
            return title
        }
        guard !body.isEmpty else { return nil }
        if body.count > 120 {
            return String(body.prefix(120)) + "…"
        }
        return body
    }

    private var hasOutstandingAgentToolCalls: Bool {
        var outstandingToolUseIDs: Set<String> = []
        var anonymousOutstandingCalls = 0

        for presentation in visibleTranscriptPresentations {
            for entry in presentation.entries where entry.role == .agent {
                switch entry.kind {
                case .toolCall:
                    if let toolUseID = normalizedToolUseID(entry.toolUseID) {
                        outstandingToolUseIDs.insert(toolUseID)
                    } else {
                        anonymousOutstandingCalls += 1
                    }
                case .toolResult:
                    if let toolUseID = normalizedToolUseID(entry.toolUseID) {
                        outstandingToolUseIDs.remove(toolUseID)
                    } else if anonymousOutstandingCalls > 0 {
                        anonymousOutstandingCalls -= 1
                    }
                default:
                    continue
                }
            }
        }

        return !outstandingToolUseIDs.isEmpty || anonymousOutstandingCalls > 0
    }

    private func normalizedToolUseID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct FlattenedTranscriptEntry {
        let messageID: String
        let sequenceText: String
        let createdAtText: String
        var entry: SessionTranscriptEntry
    }

    private func coalesceStreamingEntries(
        in presentations: [SessionTranscriptMessagePresentation]
    ) -> [SessionTranscriptMessagePresentation] {
        var flattened: [FlattenedTranscriptEntry] = []
        flattened.reserveCapacity(
            presentations.reduce(into: 0) { partialResult, presentation in
                partialResult += presentation.entries.count
            }
        )
        var openStreamIndexByToolUseID: [String: Int] = [:]

        for presentation in presentations {
            for entry in presentation.entries {
                if isStreamingReferenceEntry(entry) {
                    if let toolUseID = normalizedToolUseID(entry.toolUseID),
                       let existingIndex = openStreamIndexByToolUseID[toolUseID],
                       flattened.indices.contains(existingIndex) {
                        let existing = flattened[existingIndex].entry
                        let mergedBody = mergeStreamChunk(existing: existing.body, chunk: entry.body)
                        if mergedBody != existing.body {
                            flattened[existingIndex].entry = SessionTranscriptEntry(
                                id: existing.id,
                                role: existing.role,
                                kind: existing.kind,
                                title: existing.title,
                                body: mergedBody,
                                toolUseID: existing.toolUseID,
                                sourceType: existing.sourceType,
                                toolName: existing.toolName,
                                isSidechain: existing.isSidechain,
                                threadID: existing.threadID
                            )
                        }
                        continue
                    }

                    let appendedIndex = flattened.count
                    flattened.append(
                        FlattenedTranscriptEntry(
                            messageID: presentation.messageID,
                            sequenceText: presentation.sequenceText,
                            createdAtText: presentation.createdAtText,
                            entry: entry
                        )
                    )
                    if let toolUseID = normalizedToolUseID(entry.toolUseID) {
                        openStreamIndexByToolUseID[toolUseID] = appendedIndex
                    }
                    continue
                }

                if entry.kind == .toolResult,
                   let toolUseID = normalizedToolUseID(entry.toolUseID) {
                    openStreamIndexByToolUseID.removeValue(forKey: toolUseID)
                }

                flattened.append(
                    FlattenedTranscriptEntry(
                        messageID: presentation.messageID,
                        sequenceText: presentation.sequenceText,
                        createdAtText: presentation.createdAtText,
                        entry: entry
                    )
                )
            }
        }

        var coalesced: [SessionTranscriptMessagePresentation] = []
        coalesced.reserveCapacity(presentations.count)

        for flattenedEntry in flattened {
            if let last = coalesced.last,
               last.messageID == flattenedEntry.messageID {
                var combinedEntries = last.entries
                combinedEntries.append(flattenedEntry.entry)
                coalesced[coalesced.count - 1] = SessionTranscriptMessagePresentation(
                    messageID: last.messageID,
                    sequenceText: last.sequenceText,
                    createdAtText: last.createdAtText,
                    entries: combinedEntries
                )
                continue
            }

            coalesced.append(
                SessionTranscriptMessagePresentation(
                    messageID: flattenedEntry.messageID,
                    sequenceText: flattenedEntry.sequenceText,
                    createdAtText: flattenedEntry.createdAtText,
                    entries: [flattenedEntry.entry]
                )
            )
        }

        return coalesced
    }

    private func isStreamingReferenceEntry(_ entry: SessionTranscriptEntry) -> Bool {
        guard entry.kind == .raw else { return false }
        guard let sourceType = entry.sourceType?.lowercased() else { return false }
        return sourceType == "terminal-output" || sourceType == "tool-stream"
    }

    private func mergeStreamChunk(existing: String, chunk: String) -> String {
        SessionStreamingOutputMerger.merge(existing: existing, chunk: chunk)
    }

    private func filterReasoningEntries(
        in presentations: [SessionTranscriptMessagePresentation]
    ) -> [SessionTranscriptMessagePresentation] {
        guard !showReasoningDetails else { return presentations }

        let reasoningToolUseIDs = collectReasoningToolUseIDs(in: presentations)
        var filteredPresentations: [SessionTranscriptMessagePresentation] = []
        filteredPresentations.reserveCapacity(presentations.count)

        for presentation in presentations {
            var keptEntries: [SessionTranscriptEntry] = []
            keptEntries.reserveCapacity(presentation.entries.count)

            for entry in presentation.entries {
                let normalizedToolName = entry.toolName?.lowercased()
                let normalizedSourceType = entry.sourceType?.lowercased()
                let toolUseID = normalizedToolUseID(entry.toolUseID)
                let isReasoningTool = isReasoningToolName(normalizedToolName)
                let isReasoningStream = toolUseID.map { reasoningToolUseIDs.contains($0) } ?? false
                let shouldHideReasoningEntry =
                    entry.kind == .thinking ||
                    normalizedSourceType == "reasoning" ||
                    isReasoningTool ||
                    isReasoningStream

                if shouldHideReasoningEntry {
                    continue
                }

                keptEntries.append(entry)
            }

            guard !keptEntries.isEmpty else { continue }
            if keptEntries == presentation.entries {
                filteredPresentations.append(presentation)
            } else {
                filteredPresentations.append(
                    SessionTranscriptMessagePresentation(
                        messageID: presentation.messageID,
                        sequenceText: presentation.sequenceText,
                        createdAtText: presentation.createdAtText,
                        entries: keptEntries
                    )
                )
            }
        }

        return filteredPresentations
    }

    private func collectReasoningToolUseIDs(
        in presentations: [SessionTranscriptMessagePresentation]
    ) -> Set<String> {
        var ids: Set<String> = []
        for presentation in presentations {
            for entry in presentation.entries where entry.kind == .toolCall {
                guard isReasoningToolName(entry.toolName) else { continue }
                guard let toolUseID = normalizedToolUseID(entry.toolUseID) else { continue }
                ids.insert(toolUseID)
            }
        }
        return ids
    }

    private func isReasoningToolName(_ value: String?) -> Bool {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty else {
            return false
        }
        return normalized == "codexreasoning" ||
            normalized == "geminireasoning" ||
            normalized == "think"
    }

    private func filterSubagentEntriesAndCount(
        in presentations: [SessionTranscriptMessagePresentation]
    ) -> (presentations: [SessionTranscriptMessagePresentation], inProgressCount: Int) {
        var filteredPresentations: [SessionTranscriptMessagePresentation] = []
        filteredPresentations.reserveCapacity(presentations.count)
        var activeSubagentToolUseIDs: Set<String> = []
        var anonymousActiveSubagentToolCalls = 0
        var inProgressCount = 0

        for presentation in presentations {
            var filteredEntries: [SessionTranscriptEntry] = []
            filteredEntries.reserveCapacity(presentation.entries.count)

            for entry in presentation.entries {
                if entry.isSidechain {
                    switch entry.kind {
                    case .toolCall:
                        if let toolUseID = entry.toolUseID {
                            activeSubagentToolUseIDs.insert(toolUseID)
                        } else {
                            anonymousActiveSubagentToolCalls += 1
                        }
                        inProgressCount = activeSubagentToolUseIDs.count + anonymousActiveSubagentToolCalls
                    case .toolResult:
                        if let toolUseID = entry.toolUseID {
                            activeSubagentToolUseIDs.remove(toolUseID)
                        } else if anonymousActiveSubagentToolCalls > 0 {
                            anonymousActiveSubagentToolCalls -= 1
                        }
                        inProgressCount = activeSubagentToolUseIDs.count + anonymousActiveSubagentToolCalls
                    default:
                        break
                    }
                    continue
                }

                filteredEntries.append(entry)
            }

            guard !filteredEntries.isEmpty else { continue }
            if filteredEntries == presentation.entries {
                filteredPresentations.append(presentation)
                continue
            }
            filteredPresentations.append(
                SessionTranscriptMessagePresentation(
                    messageID: presentation.messageID,
                    sequenceText: presentation.sequenceText,
                    createdAtText: presentation.createdAtText,
                    entries: filteredEntries
                )
            )
        }

        return (filteredPresentations, inProgressCount)
    }

    private func normalizedNonNegativeInt(from value: Any?) -> Int? {
        if let intValue = value as? Int {
            return max(0, intValue)
        }
        if let number = value as? NSNumber {
            return max(0, number.intValue)
        }
        if let string = value as? String,
           let parsed = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return max(0, parsed)
        }
        return nil
    }
}

private enum DockChipTone {
    case neutral
    case primary
}

private struct PressableScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct DockChipModifier: ViewModifier {
    let tone: DockChipTone

    func body(content: Content) -> some View {
        content
            .font(.caption.monospaced().weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(chipBackground)
            )
    }

    private var chipBackground: Color {
        switch tone {
        case .neutral:
            return AppPalette.controlSurface
        case .primary:
            return AppPalette.chipPrimaryBackground
        }
    }

    private var foreground: Color {
        switch tone {
        case .neutral:
            return AppPalette.primaryText
        case .primary:
            return .white
        }
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

private struct MessagesSectionRows: View {
    let isLoading: Bool
    let errorMessage: String?
    let visibleTranscriptPresentations: [SessionTranscriptMessagePresentation]
    let liveStatusText: String?
    let transcriptBottomAnchorID: String
    let onReferenceToggle: () -> Void
    let onRetry: () -> Void

    var body: some View {
        messageSectionBadge
        if isLoading {
            TranscriptLoadingCard()
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(
                    EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
                )
        } else if let errorMessage {
            TranscriptErrorCard(error: errorMessage, onRetry: onRetry)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(
                    EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
                )
        } else if visibleTranscriptPresentations.isEmpty {
            Text("No synced messages yet for this session")
                .font(.footnote)
                .foregroundStyle(AppPalette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppPalette.chatToolBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppPalette.chatBubbleStroke, lineWidth: 1)
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(
                    EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
                )
        } else {
            ForEach(visibleTranscriptPresentations, id: \.messageID) { presentation in
                SessionTranscriptMessageRow(
                    presentation: presentation,
                    onReferenceToggle: onReferenceToggle
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(
                    EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)
                )
            }
        }

        if let liveStatusText {
            SessionTranscriptLiveStatusRow(statusText: liveStatusText)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(
                    EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)
                )
        }

        Color.clear
            .frame(height: 1)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .id(transcriptBottomAnchorID)
    }

    private var messageSectionBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.caption2)
                .foregroundStyle(AppPalette.secondaryText)
            Text("Messages")
                .font(.caption2.monospaced().weight(.bold))
                .foregroundStyle(AppPalette.secondaryText)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 2, leading: 14, bottom: 2, trailing: 14))
    }
}

private struct TranscriptLoadingCard: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(AppPalette.accent)
            Text("Loading messages…")
                .font(.footnote.monospaced())
                .foregroundStyle(AppPalette.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }
}

private struct TranscriptErrorCard: View {
    let error: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.orange)
                Text("Unable to load messages")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(AppPalette.primaryText)
            }

            Text(error)
                .font(.caption.monospaced())
                .foregroundStyle(AppPalette.secondaryText)
                .lineSpacing(1.5)

            Button(action: onRetry) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .modifier(DockChipModifier(tone: .neutral))
            }
            .buttonStyle(PressableScaleButtonStyle())
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }
}

private struct SessionTranscriptMessageRow: View {
    let presentation: SessionTranscriptMessagePresentation
    let onReferenceToggle: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: showsTimestamp ? 8 : 3) {
            if showsTimestamp {
                HStack {
                    Spacer()
                    Text(presentation.createdAtText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(AppPalette.secondaryText.opacity(0.9))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(presentation.entries) { entry in
                    SessionTranscriptLogLine(
                        entry: entry,
                        onReferenceToggle: onReferenceToggle
                    )
                }
            }
        }
        .padding(.vertical, 1)
    }

    private var showsTimestamp: Bool {
        presentation.entries.contains { entry in
            guard entry.role == .user || entry.role == .agent else { return false }
            return entry.kind == .text || entry.kind == .thinking
        }
    }
}

private struct SessionTranscriptLiveStatusRow: View {
    let statusText: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            LivePulseDot(size: 7)
                .padding(.top, 4)
            LiveStatusShimmerText(
                text: statusText,
                lineLimit: 1
            )
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LiveStatusShimmerText: View {
    let text: String
    let lineLimit: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: CGFloat = 0

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(AppPalette.secondaryText)
            .lineLimit(lineLimit)
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        let bandWidth = max(18, width * 0.24)
                        let highlightOpacity = colorScheme == .dark ? 0.40 : 0.34

                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white.opacity(highlightOpacity), location: 0.5),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: bandWidth, height: proxy.size.height * 1.7)
                        .rotationEffect(.degrees(14))
                        .offset(
                            x: (phase * (width + bandWidth * 2)) - bandWidth,
                            y: -proxy.size.height * 0.35
                        )
                    }
                    .mask(
                        Text(text)
                            .font(.footnote)
                            .lineLimit(lineLimit)
                    )
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                    .onAppear {
                        phase = 0
                        withAnimation(.linear(duration: 1.75).repeatForever(autoreverses: false)) {
                            phase = 1
                        }
                    }
                }
            }
    }
}

private struct SessionTranscriptLogLine: View {
    let entry: SessionTranscriptEntry
    let onReferenceToggle: (() -> Void)?
    @State private var isExpanded = false

    var body: some View {
        if isSystemEvent {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryText)
                Text(systemEventText)
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(AppPalette.chatToolBackground)
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 2)
        } else if isCollapsibleReferenceLogEntry {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    onReferenceToggle?()
                    withAnimation(.easeOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(AppPalette.terminalLineTool)
                            .padding(.top, 1)
                        Text(collapsibleTitle)
                            .font(.caption2.monospaced().weight(.semibold))
                            .foregroundStyle(AppPalette.terminalLineTool)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.body)
                            .font(bodyFont)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .lineSpacing(1.5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, 14)
                    .padding(.top, 1)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(AppPalette.terminalLineTool.opacity(0.45))
                            .frame(width: 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if isMainMessageEntry {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(roleColor)
                        .frame(width: 6, height: 6)
                    Text(roleLabel)
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(roleColor)
                    if let title = entry.title, !title.isEmpty {
                        Text(title)
                            .font(.caption2.monospaced())
                            .foregroundStyle(AppPalette.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                Text(entry.body)
                    .font(.callout.monospaced())
                    .foregroundStyle(AppPalette.primaryText)
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .lineSpacing(2.2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(roleColor.opacity(0.45))
                    .frame(width: 2)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if let title = entry.title, !title.isEmpty {
                    Text(title)
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(AppPalette.terminalLineTool)
                }
                Text(entry.body)
                    .font(bodyFont)
                    .foregroundStyle(AppPalette.secondaryText)
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .lineSpacing(1.5)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
    }

    private var isSystemEvent: Bool {
        entry.role == .system && entry.kind == .event
    }

    private var systemEventText: String {
        if let title = entry.title, !title.isEmpty {
            return "\(title): \(entry.body)"
        }
        return entry.body
    }

    private var bubbleColor: Color {
        if entry.role == .user {
            return AppPalette.chatUserBubble
        }
        return AppPalette.chatAgentBubble
    }

    private var roleLabel: String {
        entry.role == .user ? "user" : "assistant"
    }

    private var roleColor: Color {
        entry.role == .user ? AppPalette.terminalLineUser : AppPalette.terminalLineAgent
    }

    private var isCollapsibleToolEntry: Bool {
        entry.kind == .toolCall || entry.kind == .toolResult || isEditFilesEntry
    }

    private var isCollapsibleReferenceLogEntry: Bool {
        isCollapsibleToolEntry || entry.kind == .raw
    }

    private var isMainMessageEntry: Bool {
        guard entry.role == .user || entry.role == .agent else { return false }
        switch entry.kind {
        case .text, .thinking:
            return true
        default:
            return false
        }
    }

    private var collapsibleTitle: String {
        if isEditFilesEntry {
            return "Edit files"
        }
        if let title = entry.title, !title.isEmpty {
            return title
        }
        switch entry.kind {
        case .toolCall:
            return "Tool call"
        case .toolResult:
            return "Tool result"
        default:
            return "Details"
        }
    }

    private var isEditFilesEntry: Bool {
        let normalizedTitle = (entry.title ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalizedTitle.contains("edit files") {
            return true
        }

        let normalizedBody = entry.body.lowercased()
        return normalizedBody.contains("apply_patch") || normalizedBody.contains("*** begin patch")
    }

    private var bodyFont: Font {
        switch entry.kind {
        case .toolCall, .toolResult, .raw:
            return .footnote.monospaced()
        default:
            return .subheadline
        }
    }
}

private struct LivePulseDot: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(AppPalette.liveActivity)
            .frame(width: size, height: size)
            .scaleEffect(reduceMotion ? 1 : (isAnimating ? 1.07 : 0.94))
            .opacity(reduceMotion ? 1 : (isAnimating ? 1 : 0.82))
            .shadow(
                color: AppPalette.liveActivity.opacity(reduceMotion ? 0.12 : (isAnimating ? 0.26 : 0.14)),
                radius: reduceMotion ? 0 : 4,
                y: 0
            )
            .overlay {
                Circle()
                    .stroke(AppPalette.liveActivity.opacity(0.55), lineWidth: 1)
                    .scaleEffect(reduceMotion ? 1 : (isAnimating ? 1.32 : 1.0))
                    .opacity(reduceMotion ? 0.2 : (isAnimating ? 0.08 : 0.32))
            }
            .onAppear {
                guard !reduceMotion else {
                    isAnimating = false
                    return
                }
                isAnimating = false
                withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
            .onChange(of: reduceMotion) { _, shouldReduceMotion in
                if shouldReduceMotion {
                    isAnimating = false
                    return
                }
                withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
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
