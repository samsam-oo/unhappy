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

    private static let customModelOverrideOption = "__custom_model_override__"
    private static let modelPickerInheritOption = "__model_inherit__"
    private static let modelPickerResetOption = "__model_reset__"
    private static let modelPickerCustomOption = "__model_custom__"
    private static let modelPickerPresetPrefix = "__model_preset__:"
    private static let effortPickerInheritOption = "__effort_inherit__"
    private static let effortPickerPresetPrefix = "__effort_preset__:"

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
                } else if viewModel.selectedSessionMessages.isEmpty {
                    Text("No synced messages yet for this session")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.selectedSessionMessages) { message in
                        SessionTranscriptMessageRow(
                            presentation: transcriptPresentation(for: message)
                        )
                        .listRowSeparator(.hidden)
                        .listRowInsets(
                            EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
                        )
                    }
                }
            }

        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
        .simultaneousGesture(
            TapGesture().onEnded {
                focusedComposerField = nil
            }
        )
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
            if !availableEffortSelections.contains(selectedEffortOverride),
               let first = availableEffortSelections.first {
                selectedEffortOverride = first
            }
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
                .focused($focusedComposerField, equals: .message)

            if applyModelOverride && selectedModelOverrideOption == Self.customModelOverrideOption {
                TextField("Custom model id", text: $modelOverrideDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                    .focused($focusedComposerField, equals: .customModel)
            }

            HStack(spacing: 10) {
                Button(viewModel.isSendingMessage(sessionID: session.id) ? "Sending…" : "Send") {
                    submitDraftMessage(with: .queue)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    viewModel.isSendingMessage(sessionID: session.id) ||
                    draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                Button {
                    submitDraftMessage(with: .immediate)
                } label: {
                    Label("Now", systemImage: "bolt.fill")
                }
                .buttonStyle(.bordered)
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
        guard let flavor = parsedSessionFlavor else { return [] }
        switch flavor {
        case .codex:
            return [
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
                Picker(
                    selection: modelPickerSelection,
                    label: Label(
                        "Model: \(selectedModelOverrideLabel)",
                        systemImage: "cpu"
                    )
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                ) {
                    ForEach(modelPickerOptions, id: \.id) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .pickerStyle(.menu)

                if supportsReasoningEffortOverride {
                    Picker(
                        selection: effortPickerSelection,
                        label: Label(
                            "Reasoning: \(selectedReasoningOverrideLabel)",
                            systemImage: "brain.head.profile"
                        )
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                    ) {
                        ForEach(effortPickerOptions, id: \.id) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

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
            focusedComposerField = nil
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

    private var selectedModelOverrideLabel: String {
        guard applyModelOverride else { return "Inherit" }
        switch selectedModelOverrideOption {
        case Self.customModelOverrideOption:
            let normalized = modelOverrideDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? "Custom" : normalized
        case "":
            return "Default"
        default:
            return selectedModelOverrideOption
        }
    }

    private var selectedReasoningOverrideLabel: String {
        guard applyEffortOverride else { return "Inherit" }
        return selectedEffortOverride.label
    }

    private struct PickerOption: Identifiable {
        let id: String
        let label: String
    }

    private var modelPickerOptions: [PickerOption] {
        var options: [PickerOption] = [
            PickerOption(
                id: Self.modelPickerInheritOption,
                label: "Inherit session model"
            ),
            PickerOption(
                id: Self.modelPickerResetOption,
                label: "Reset to default model"
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
        var options: [PickerOption] = [
            PickerOption(
                id: Self.effortPickerInheritOption,
                label: "Inherit session reasoning"
            )
        ]
        options.append(
            contentsOf: availableEffortSelections.map { effort in
                PickerOption(
                    id: Self.effortPickerPresetPrefix + effort.rawValue,
                    label: effort == .auto ? "Auto" : effort.label
                )
            }
        )
        return options
    }

    private var modelPickerSelection: Binding<String> {
        Binding(
            get: {
                if !applyModelOverride {
                    return Self.modelPickerInheritOption
                }
                if selectedModelOverrideOption == Self.customModelOverrideOption {
                    return Self.modelPickerCustomOption
                }
                if selectedModelOverrideOption.isEmpty {
                    return Self.modelPickerResetOption
                }
                return Self.modelPickerPresetPrefix + selectedModelOverrideOption
            },
            set: { value in
                switch value {
                case Self.modelPickerInheritOption:
                    applyModelOverride = false
                    selectedModelOverrideOption = ""
                    focusedComposerField = nil
                case Self.modelPickerResetOption:
                    applyModelOverride = true
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
                guard applyEffortOverride else {
                    return Self.effortPickerInheritOption
                }
                return Self.effortPickerPresetPrefix + selectedEffortOverride.rawValue
            },
            set: { value in
                if value == Self.effortPickerInheritOption {
                    applyEffortOverride = false
                    selectedEffortOverride = .auto
                    return
                }
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

    private var parsedSessionFlavor: SessionComposerFlavor? {
        guard let data = currentSession.metadata.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["flavor"] as? String else {
            return nil
        }
        return SessionComposerFlavor(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private func transcriptPresentation(
        for message: APISessionMessage
    ) -> SessionTranscriptMessagePresentation {
        SessionTranscriptPresentationBuilder.make(
            from: message,
            dataEncryptionKey: currentSession.dataEncryptionKey
        )
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(presentation.sequenceText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(presentation.createdAtText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(presentation.entries) { entry in
                    SessionTranscriptLogLine(entry: entry)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .padding(.vertical, 2)
    }
}

private struct SessionTranscriptLogLine: View {
    let entry: SessionTranscriptEntry

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

    private var bodyFont: Font {
        switch entry.kind {
        case .toolCall, .toolResult, .raw:
            return .footnote.monospaced()
        default:
            return .subheadline
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
