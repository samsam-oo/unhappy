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

    private enum SessionQuickToolsAnchor: String {
        case model
        case effort
        case info
        case files
        case review
        case worktree
    }

    private struct CachedTranscriptPresentation: Equatable {
        let sourceMessage: APISessionMessage
        let dataEncryptionKey: String?
        let presentation: SessionTranscriptMessagePresentation
    }

    private static let customModelOverrideOption = "__custom_model_override__"
    private static let modelPickerDefaultOption = "__model_default__"
    private static let modelPickerCustomOption = "__model_custom__"
    private static let modelPickerPresetPrefix = "__model_preset__:"
    private static let effortPickerPresetPrefix = "__effort_preset__:"
    private static let transcriptBottomAnchorID = "__session_transcript_bottom__"

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
    @State private var serverModelOverrideOptions: [String] = []
    @State private var shouldFollowTranscript = true
    @State private var scrollToBottomRequestID = UUID()
    @State private var transcriptPresentationCache: [String: CachedTranscriptPresentation] = [:]
    @State private var cachedVisibleTranscriptPresentations: [SessionTranscriptMessagePresentation] = []
    @State private var subAgentInProgressCount = 0
    @State private var quickToolsScrollPositionID: String? = SessionQuickToolsAnchor.model.rawValue
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
                        Text(SessionTimestampPresentation.updatedLabel(for: currentSession.updatedAt))
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
                    } else if visibleTranscriptPresentations.isEmpty {
                        Text("No synced messages yet for this session")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(visibleTranscriptPresentations, id: \.messageID) { presentation in
                            SessionTranscriptMessageRow(
                                presentation: presentation,
                                onReferenceToggle: {
                                    shouldFollowTranscript = false
                                }
                            )
                            .listRowSeparator(.hidden)
                            .listRowInsets(
                                EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12)
                            )
                        }
                    }

                    if let liveStatusText {
                        SessionTranscriptLiveStatusRow(statusText: liveStatusText)
                            .listRowSeparator(.hidden)
                            .listRowInsets(
                                EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12)
                            )
                    }

                    Color.clear
                        .frame(height: 1)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .id(Self.transcriptBottomAnchorID)
                }

            }
            .listStyle(.plain)
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
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if subAgentInProgressCount > 0 {
                        subAgentLiveBar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    bottomDock
                }
                .animation(.easeInOut(duration: 0.2), value: subAgentInProgressCount > 0)
            }
            .navigationTitle(currentSessionTitle)
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
                refreshTranscriptPresentationCache(
                    messages: viewModel.selectedSessionMessages,
                    dataEncryptionKey: currentSession.dataEncryptionKey
                )
                scrollTranscriptToBottom(using: scrollProxy, animated: false)
            }
            .onChange(of: viewModel.selectedSessionMessages) { _, messages in
                refreshTranscriptPresentationCache(
                    messages: messages,
                    dataEncryptionKey: currentSession.dataEncryptionKey
                )
            }
            .onChange(of: currentSession.dataEncryptionKey) { _, dataEncryptionKey in
                refreshTranscriptPresentationCache(
                    messages: viewModel.selectedSessionMessages,
                    dataEncryptionKey: dataEncryptionKey
                )
            }
            .onChange(of: visibleTranscriptMessageIDs) { oldIDs, newIDs in
                guard shouldFollowTranscript else { return }
                // Avoid List/UICollectionView out-of-bounds assertions during shrink updates.
                guard newIDs.count >= oldIDs.count else { return }
                scrollTranscriptToBottom(using: scrollProxy)
            }
            .onChange(of: scrollToBottomRequestID) { _, _ in
                scrollTranscriptToBottom(using: scrollProxy)
            }
            .onChange(of: focusedComposerField) { _, focusedField in
                guard focusedField != nil else { return }
                shouldFollowTranscript = true
                scrollTranscriptToBottom(using: scrollProxy)
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

    private var bottomDock: some View {
        VStack(spacing: 8) {
            composerBar
            quickToolsBar
        }
        .padding(.top, 8)
        .background(.ultraThinMaterial)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).updating($isInteractingWithBottomDock) { _, state, _ in
                state = true
            }
        )
    }

    private var subAgentLiveBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
            Text("\(subAgentInProgressCount) sub-agents")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.green)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.green.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.green.opacity(0.4), lineWidth: 1)
        )
        .padding(.horizontal, 12)
    }

    private var composerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            let queuedComposerMessages = viewModel.queuedComposerMessages(for: currentSession.id)
            if !queuedComposerMessages.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    let visibleQueuedMessages = Array(queuedComposerMessages.suffix(4))
                    let hiddenCount = max(0, queuedComposerMessages.count - visibleQueuedMessages.count)

                    HStack(spacing: 6) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Steer Stack")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if hiddenCount > 0 {
                            Text("+\(hiddenCount)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(Array(visibleQueuedMessages.enumerated()), id: \.offset) { _, text in
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(text)
                                .font(.footnote)
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            Button("Edit") {
                                draftMessage = text
                                focusedComposerField = .message
                            }
                            .buttonStyle(.borderless)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.secondary.opacity(0.12))
                        )
                    }
                }
            }

            TextField("Ask for follow-up changes", text: $draftMessage, axis: .vertical)
                .lineLimit(2...6)
                .textInputAutocapitalization(.sentences)
                .focused($focusedComposerField, equals: .message)

            if applyModelOverride && selectedModelOverrideOption == Self.customModelOverrideOption {
                TextField("Custom model id", text: $modelOverrideDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                    .focused($focusedComposerField, equals: .customModel)
            }

            HStack(spacing: 10) {
                Spacer(minLength: 0)

                dockChipButton(
                    title: "Queue",
                    systemImage: "clock",
                    isDisabled: viewModel.isSendingMessage(sessionID: session.id)
                ) {
                    submitDraftMessage(with: .queue)
                }

                dockChipButton(
                    title: viewModel.isSendingMessage(sessionID: session.id) ? "Sending…" : "Send",
                    systemImage: "paperplane.fill",
                    isDisabled: viewModel.isSendingMessage(sessionID: session.id)
                ) {
                    submitDraftMessage(with: .immediate)
                }
            }

            if let error = viewModel.sendMessageErrorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 12)
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
            HStack(spacing: 8) {
                modelMenuButton
                    .id(SessionQuickToolsAnchor.model.rawValue)

                if supportsReasoningEffortOverride {
                    effortMenuButton
                        .id(SessionQuickToolsAnchor.effort.rawValue)
                }

                quickToolButton(
                    title: "Info",
                    systemImage: "info.circle",
                    tool: .info
                )
                .id(SessionQuickToolsAnchor.info.rawValue)
                quickToolButton(
                    title: "Files",
                    systemImage: "doc.text",
                    tool: .files
                )
                .id(SessionQuickToolsAnchor.files.rawValue)
                quickToolButton(
                    title: "Diff",
                    systemImage: "doc.text.magnifyingglass",
                    tool: .review
                )
                .id(SessionQuickToolsAnchor.review.rawValue)
                quickToolButton(
                    title: "Worktree",
                    systemImage: "checkmark.circle",
                    tool: .worktree
                )
                .id(SessionQuickToolsAnchor.worktree.rawValue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $quickToolsScrollPositionID, anchor: .leading)
        .onChange(of: supportsReasoningEffortOverride) { _, enabled in
            guard !enabled else { return }
            if quickToolsScrollPositionID == SessionQuickToolsAnchor.effort.rawValue {
                quickToolsScrollPositionID = SessionQuickToolsAnchor.model.rawValue
            }
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
                .modifier(DockChipModifier())
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
                .modifier(DockChipModifier())
        }
        .tint(.primary)
    }

    private func dockChipButton(
        title: String,
        systemImage: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .modifier(DockChipModifier())
        }
        .buttonStyle(.plain)
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
        transcriptPresentationCache = nextCache
        if cachedVisibleTranscriptPresentations != filtered.presentations {
            cachedVisibleTranscriptPresentations = filtered.presentations
        }
        let normalizedInProgressCount = currentSession.active ? filtered.inProgressCount : 0
        if subAgentInProgressCount != normalizedInProgressCount {
            subAgentInProgressCount = normalizedInProgressCount
        }
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

        if let latestAgentLiveStatusText {
            if shouldShowAgentLiveStatus {
                return latestAgentLiveStatusText
            }
        }

        return nil
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

    private func filterSubagentEntriesAndCount(
        in presentations: [SessionTranscriptMessagePresentation]
    ) -> (presentations: [SessionTranscriptMessagePresentation], inProgressCount: Int) {
        var filteredPresentations: [SessionTranscriptMessagePresentation] = []
        filteredPresentations.reserveCapacity(presentations.count)
        var activeSubagentToolUseIDs: Set<String> = []
        var inProgressCount = 0

        for presentation in presentations {
            var filteredEntries: [SessionTranscriptEntry] = []
            filteredEntries.reserveCapacity(presentation.entries.count)

            for entry in presentation.entries {
                if isSubagentToolCallEntry(entry) {
                    if let toolUseID = entry.toolUseID {
                        activeSubagentToolUseIDs.insert(toolUseID)
                    }
                    inProgressCount += 1
                    continue
                }

                if isSubagentToolResultEntry(entry, activeToolUseIDs: activeSubagentToolUseIDs) {
                    if let toolUseID = entry.toolUseID {
                        activeSubagentToolUseIDs.remove(toolUseID)
                    }
                    inProgressCount = max(0, inProgressCount - 1)
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

    private func isSubagentToolCallEntry(_ entry: SessionTranscriptEntry) -> Bool {
        guard entry.kind == .toolCall else { return false }
        let normalizedTitle = normalizedEntryTitle(entry)
        if normalizedTitle.contains("run task") ||
            normalizedTitle.contains("sub-agent") ||
            normalizedTitle.contains("subagent") {
            return true
        }

        let normalizedBody = entry.body.lowercased()
        return normalizedBody.contains("spawn_agent") ||
            normalizedBody.contains("subagent_type")
    }

    private func isSubagentToolResultEntry(
        _ entry: SessionTranscriptEntry,
        activeToolUseIDs: Set<String>
    ) -> Bool {
        guard entry.kind == .toolResult else { return false }
        if let toolUseID = entry.toolUseID,
           activeToolUseIDs.contains(toolUseID) {
            return true
        }

        let normalizedTitle = normalizedEntryTitle(entry)
        if normalizedTitle.contains("run task") ||
            normalizedTitle.contains("sub-agent") ||
            normalizedTitle.contains("subagent") {
            return true
        }

        let normalizedBody = entry.body.lowercased()
        return normalizedBody.contains("spawn_agent") ||
            normalizedBody.contains("subagent_notification")
    }

    private func normalizedEntryTitle(_ entry: SessionTranscriptEntry) -> String {
        (entry.title ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private struct DockChipModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.12), in: Capsule())
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

private struct SessionTranscriptMessageRow: View {
    let presentation: SessionTranscriptMessagePresentation
    let onReferenceToggle: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: showsTimestamp ? 6 : 2) {
            if showsTimestamp {
                HStack {
                    Spacer()
                    Text(presentation.createdAtText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
    @State private var isExpanded = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                LivePulseDot(size: 7)
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? 4 : 1)
                Spacer(minLength: 0)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .foregroundStyle(.secondary)
                Text(systemEventText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 2)
        } else if isCollapsibleReferenceLogEntry {
            VStack(alignment: .leading, spacing: 1) {
                Button {
                    onReferenceToggle?()
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(collapsibleTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(entry.body)
                            .font(bodyFont)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if isMainMessageEntry {
            VStack(alignment: .leading, spacing: 4) {
                if let title = entry.title, !title.isEmpty {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(entry.body)
                    .font(bodyFont)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineLimit(nil)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(bubbleColor)
            )
            .frame(
                maxWidth: .infinity,
                alignment: entry.role == .user ? .trailing : .leading
            )
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if let title = entry.title, !title.isEmpty {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(entry.body)
                    .font(bodyFont)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineLimit(nil)
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
            return Color.blue.opacity(0.12)
        }
        return Color.primary.opacity(0.04)
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
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: size, height: size)
            .scaleEffect(isAnimating ? 1.0 : 0.78)
            .opacity(isAnimating ? 1.0 : 0.5)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
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
