import SwiftUI
import CoreKit

@MainActor
public struct NewSessionView: View {
    private let serverURLString: String
    private let token: String
    private let defaultAgent: APISessionSpawnAgent
    private let onSessionSpawned: @MainActor (String?) -> Void

    @StateObject private var viewModel: NewSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showSaveProfilePrompt = false
    @State private var draftProfileName = ""
    @State private var showCodexThreadsSheet = false
    @State private var showClaudeSessionsSheet = false
    @State private var showDirectoryBrowserSheet = false
    @State private var directoryBrowserFilterText = ""
    @State private var directoryBrowserPathDraft = ""
    @FocusState private var focusedField: FocusedField?

    public init(
        serverURLString: String,
        token: String,
        defaultAgent: APISessionSpawnAgent = .claude,
        makeViewModel: @escaping @MainActor () -> NewSessionViewModel,
        onSessionSpawned: @escaping @MainActor (String?) -> Void = { _ in }
    ) {
        self.serverURLString = serverURLString
        self.token = token
        self.defaultAgent = defaultAgent
        self.onSessionSpawned = onSessionSpawned
        _viewModel = StateObject(wrappedValue: makeViewModel())
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Machine") {
                    if viewModel.isLoadingMachines {
                        HStack {
                            ProgressView()
                            Text("Loading machines…")
                                .foregroundStyle(.secondary)
                        }
                    } else if viewModel.machines.isEmpty {
                        Text("No machines available")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Machine", selection: machineSelectionBinding) {
                            ForEach(viewModel.machines) { machine in
                                Text(NewSessionMachinePresentation.displayName(for: machine)).tag(machine.id)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }

                Section("Directory") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Selected Directory")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(viewModel.directoryPath)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button("Choose Folder") {
                        directoryBrowserPathDraft = viewModel.directoryPath
                        directoryBrowserFilterText = ""
                        showDirectoryBrowserSheet = true
                    }
                    .disabled(viewModel.selectedMachineID == nil || viewModel.isLoadingDirectory)

                    if viewModel.isLoadingDirectory {
                        HStack {
                            ProgressView()
                            Text("Loading directory…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Profiles") {
                    if viewModel.profiles.isEmpty {
                        Text("No saved profiles")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.profiles) { profile in
                            Button {
                                Task {
                                    await viewModel.applyProfile(
                                        id: profile.id,
                                        serverURLString: serverURLString,
                                        token: token
                                    )
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name)
                                        .lineLimit(1)
                                    Text("\(profile.agent.rawValue) • \(profile.directoryPath)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    Task {
                                        await viewModel.deleteProfile(id: profile.id)
                                    }
                                }
                            }
                        }
                    }

                    Button("Save Current As Profile") {
                        draftProfileName = ""
                        showSaveProfilePrompt = true
                    }
                }

                Section("Agent") {
                    Picker("Agent", selection: agentSelectionBinding) {
                        Text("Claude").tag(APISessionSpawnAgent.claude)
                        Text("Codex").tag(APISessionSpawnAgent.codex)
                        Text("Gemini").tag(APISessionSpawnAgent.gemini)
                    }
                }

                Section("Advanced") {
                    if viewModel.isLoadingModels {
                        HStack {
                            ProgressView()
                            Text("Loading models…")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker("Model", selection: $viewModel.selectedModel) {
                        Text("Default").tag("")
                        ForEach(viewModel.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .disabled(viewModel.availableModels.isEmpty && viewModel.isLoadingModels)

                    if let error = viewModel.modelsErrorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                        Button("Retry Models") {
                            Task {
                                await viewModel.loadModels(
                                    serverURLString: serverURLString,
                                    token: token
                                )
                            }
                        }
                        .font(.footnote)
                    }

                    Picker("Reasoning Effort", selection: $viewModel.selectedReasoningEffort) {
                        ForEach(viewModel.availableReasoningEfforts, id: \.self) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    Button(viewModel.isLoadingCodexThreads ? "Loading Codex Sessions…" : codexSelectionButtonTitle) {
                        showCodexThreadsSheet = true
                        Task {
                            await viewModel.loadCodexThreads(
                                serverURLString: serverURLString,
                                token: token
                            )
                        }
                    }
                    .disabled(
                        viewModel.selectedMachineID == nil ||
                        viewModel.isLoadingCodexThreads ||
                        viewModel.isLoadingMoreCodexThreads
                    )
                    if let error = viewModel.codexThreadsErrorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if !viewModel.codexResumeThreadID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Selected Codex Session")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(viewModel.codexResumeThreadID)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                            Button("Clear Codex Selection") {
                                viewModel.clearCodexSelection()
                            }
                            .font(.footnote)
                        }
                    }

                    Button(viewModel.isLoadingClaudeSessions ? "Loading Claude Sessions…" : claudeSelectionButtonTitle) {
                        showClaudeSessionsSheet = true
                        Task {
                            await viewModel.loadClaudeSessions(
                                serverURLString: serverURLString,
                                token: token
                            )
                        }
                    }
                    .disabled(
                        viewModel.selectedMachineID == nil ||
                        viewModel.isLoadingClaudeSessions ||
                        viewModel.isLoadingMoreClaudeSessions
                    )
                    if let error = viewModel.claudeSessionsErrorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if !viewModel.claudeResumeSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Selected Claude Session")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(viewModel.claudeResumeSessionID)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                            Button("Clear Claude Selection") {
                                viewModel.clearClaudeSelection()
                            }
                            .font(.footnote)
                        }
                    }

                    TextField("Session token (optional)", text: $viewModel.sessionToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .sessionToken)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Environment Variables (KEY=VALUE)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $viewModel.environmentVariablesText)
                            .font(.footnote.monospaced())
                            .frame(minHeight: 96)
                            .focused($focusedField, equals: .environmentVariables)
                        Text("One variable per line. Empty lines and # comments are ignored.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Action") {
                    Button(viewModel.isSpawning ? "Starting…" : primaryActionTitle) {
                        Task {
                            let success = await viewModel.startSession(
                                serverURLString: serverURLString,
                                token: token
                            )
                            if success {
                                onSessionSpawned(viewModel.spawnedSessionID)
                                dismiss()
                            }
                        }
                    }
                    .disabled(
                        viewModel.isSpawning ||
                        viewModel.selectedMachineID == nil ||
                        viewModel.directoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    if let approvalDirectory = viewModel.approvalDirectory {
                        Text("Directory creation approval needed: \(approvalDirectory)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Create Directory And Continue") {
                            Task {
                                let success = await viewModel.continueWithDirectoryApproval(
                                    serverURLString: serverURLString,
                                    token: token
                                )
                                if success {
                                    onSessionSpawned(viewModel.spawnedSessionID)
                                    dismiss()
                                }
                            }
                        }
                        .disabled(viewModel.isSpawning)
                    }
                }

                if let info = viewModel.infoMessage {
                    Section("Status") {
                        Text(info)
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                }
                if let error = viewModel.errorMessage {
                    Section("Error") {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                TapGesture().onEnded {
                    focusedField = nil
                }
            )
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Save Profile", isPresented: $showSaveProfilePrompt) {
                TextField("Profile Name", text: $draftProfileName)
                Button("Save") {
                    Task {
                        await viewModel.saveCurrentAsProfile(named: draftProfileName)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Saves current machine/path/agent/advanced values.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showCodexThreadsSheet) {
                NavigationStack {
                    List {
                        if viewModel.isLoadingCodexThreads && viewModel.codexThreads.isEmpty {
                            ProgressView("Loading Codex sessions…")
                        } else if viewModel.codexThreads.isEmpty {
                            if let error = viewModel.codexThreadsErrorMessage {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Unable to load Codex sessions")
                                        .font(.headline)
                                    Text(error)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Button("Retry") {
                                        Task {
                                            await viewModel.loadCodexThreads(
                                                serverURLString: serverURLString,
                                                token: token
                                            )
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                            } else {
                                ContentUnavailableView(
                                    "No existing Codex sessions",
                                    systemImage: "list.bullet",
                                    description: Text("Start one in CLI first, then refresh here.")
                                )
                            }
                        } else {
                            ForEach(viewModel.codexThreads) { thread in
                                Button {
                                    viewModel.selectCodexThread(thread)
                                    showCodexThreadsSheet = false
                                    Task {
                                        await viewModel.loadDirectory(
                                            serverURLString: serverURLString,
                                            token: token
                                        )
                                    }
                                } label: {
                                    CodexThreadSelectionRow(thread: thread)
                                }
                                .buttonStyle(.plain)
                            }

                            if viewModel.isLoadingMoreCodexThreads {
                                HStack {
                                    Spacer()
                                    ProgressView("Loading more…")
                                    Spacer()
                                }
                            } else if viewModel.codexThreadsHasNext {
                                Button("Load More") {
                                    Task {
                                        await viewModel.loadMoreCodexThreads(
                                            serverURLString: serverURLString,
                                            token: token
                                        )
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                            }

                            if let error = viewModel.codexThreadsErrorMessage {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Unable to load additional Codex sessions")
                                        .font(.subheadline.weight(.semibold))
                                    Text(error)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Button("Retry") {
                                        Task {
                                            await viewModel.loadMoreCodexThreads(
                                                serverURLString: serverURLString,
                                                token: token
                                            )
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    .navigationTitle("Codex Sessions")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showCodexThreadsSheet = false }
                        }
                    }
                    .refreshable {
                        await viewModel.loadCodexThreads(
                            serverURLString: serverURLString,
                            token: token
                        )
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showDirectoryBrowserSheet) {
                NavigationStack {
                    VStack(spacing: 0) {
                        Form {
                            Section("Current Path") {
                                TextField("Go to path", text: $directoryBrowserPathDraft)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .submitLabel(.done)
                                    .disabled(
                                        viewModel.selectedMachineID == nil ||
                                        viewModel.isLoadingDirectory
                                    )
                                    .focused($focusedField, equals: .directoryPath)
                                    .onSubmit {
                                        Task {
                                            await loadDirectoryFromBrowserPath(directoryBrowserPathDraft)
                                        }
                                    }

                                Button {
                                    Task {
                                        await goToParentDirectoryFromBrowser()
                                    }
                                } label: {
                                    Label("Up One Level", systemImage: "folder")
                                }
                                .disabled(viewModel.selectedMachineID == nil || viewModel.isLoadingDirectory)
                            }

                            Section("Folders") {
                                TextField("Filter folders", text: $directoryBrowserFilterText)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .focused($focusedField, equals: .directoryFilter)

                                if viewModel.isLoadingDirectory {
                                    HStack {
                                        ProgressView()
                                        Text("Loading folders…")
                                            .foregroundStyle(.secondary)
                                    }
                                } else if let error = viewModel.errorMessage,
                                          !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(error)
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                    Button("Retry") {
                                        Task {
                                            await loadDirectoryFromBrowserPath(directoryBrowserPathDraft)
                                        }
                                    }
                                } else if filteredDirectoryBrowserEntries.isEmpty {
                                    ContentUnavailableView(
                                        "No folders found",
                                        systemImage: "folder.badge.questionmark",
                                        description: Text("Try a different path or clear the filter.")
                                    )
                                } else {
                                    ForEach(filteredDirectoryBrowserEntries) { entry in
                                        Button {
                                            Task {
                                                await viewModel.selectDirectoryEntry(
                                                    entry,
                                                    serverURLString: serverURLString,
                                                    token: token
                                                )
                                                directoryBrowserPathDraft = viewModel.directoryPath
                                            }
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: "folder")
                                                    .foregroundStyle(Color.accentColor)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(entry.name)
                                                        .lineLimit(1)
                                                    Text(directoryEntryFullPath(entry))
                                                        .font(.caption.monospaced())
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                        .truncationMode(.middle)
                                                }
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.caption)
                                                    .foregroundStyle(.tertiary)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            focusedField = nil
                        }
                    )
                    .navigationTitle("Choose Folder")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { showDirectoryBrowserSheet = false }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Use This Folder") {
                                showDirectoryBrowserSheet = false
                            }
                        }
                    }
                    .task {
                        if directoryBrowserPathDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            directoryBrowserPathDraft = viewModel.directoryPath
                        }
                        await loadDirectoryFromBrowserPath(directoryBrowserPathDraft)
                    }
                }
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showClaudeSessionsSheet) {
                NavigationStack {
                    List {
                        if viewModel.isLoadingClaudeSessions && viewModel.claudeSessions.isEmpty {
                            ProgressView("Loading Claude sessions…")
                        } else if viewModel.claudeSessions.isEmpty {
                            if let error = viewModel.claudeSessionsErrorMessage {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Unable to load Claude sessions")
                                        .font(.headline)
                                    Text(error)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Button("Retry") {
                                        Task {
                                            await viewModel.loadClaudeSessions(
                                                serverURLString: serverURLString,
                                                token: token
                                            )
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                            } else {
                                ContentUnavailableView(
                                    "No existing Claude sessions",
                                    systemImage: "list.bullet.rectangle",
                                    description: Text("Start one in CLI first, then refresh here.")
                                )
                            }
                        } else {
                            ForEach(viewModel.claudeSessions) { session in
                                Button {
                                    viewModel.selectClaudeSession(session)
                                    showClaudeSessionsSheet = false
                                    Task {
                                        await viewModel.loadDirectory(
                                            serverURLString: serverURLString,
                                            token: token
                                        )
                                    }
                                } label: {
                                    ClaudeSessionSelectionRow(session: session)
                                }
                                .buttonStyle(.plain)
                            }

                            if viewModel.isLoadingMoreClaudeSessions {
                                HStack {
                                    Spacer()
                                    ProgressView("Loading more…")
                                    Spacer()
                                }
                            } else if viewModel.claudeSessionsHasNext {
                                Button("Load More") {
                                    Task {
                                        await viewModel.loadMoreClaudeSessions(
                                            serverURLString: serverURLString,
                                            token: token
                                        )
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                            }

                            if let error = viewModel.claudeSessionsErrorMessage {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Unable to load additional Claude sessions")
                                        .font(.subheadline.weight(.semibold))
                                    Text(error)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Button("Retry") {
                                        Task {
                                            await viewModel.loadMoreClaudeSessions(
                                                serverURLString: serverURLString,
                                                token: token
                                            )
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    .navigationTitle("Claude Sessions")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showClaudeSessionsSheet = false }
                        }
                    }
                    .refreshable {
                        await viewModel.loadClaudeSessions(
                            serverURLString: serverURLString,
                            token: token
                        )
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .task(id: "\(serverURLString)|\(token)") {
                viewModel.setInitialSelectedAgent(defaultAgent)
                await viewModel.loadMachines(serverURLString: serverURLString, token: token)
            }
        }
    }

    private var filteredDirectoryBrowserEntries: [APIMachineDirectoryEntry] {
        let folders = viewModel.directoryEntries.filter { $0.type == "directory" }
        let trimmedFilter = directoryBrowserFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFilter.isEmpty else {
            return folders
        }
        return folders.filter { entry in
            entry.name.localizedCaseInsensitiveContains(trimmedFilter)
        }
    }

    private func directoryEntryFullPath(_ entry: APIMachineDirectoryEntry) -> String {
        let current = viewModel.directoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = current.isEmpty ? "~" : current
        let trimmedName = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else { return path }
        if trimmedName == "." { return path }
        if trimmedName == ".." { return parentDirectoryPath(from: path) }
        if trimmedName.hasPrefix("/") { return trimmedName }
        if path == "/" { return "/" + trimmedName }
        if path.hasSuffix("/") { return path + trimmedName }
        if path == "~" { return "~/" + trimmedName }
        return path + "/" + trimmedName
    }

    private func loadDirectoryFromBrowserPath(_ path: String) async {
        viewModel.directoryPath = path
        await viewModel.loadDirectory(
            serverURLString: serverURLString,
            token: token
        )
        directoryBrowserPathDraft = viewModel.directoryPath
    }

    private func goToParentDirectoryFromBrowser() async {
        let current = viewModel.directoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = parentDirectoryPath(from: current.isEmpty ? "~" : current)
        await loadDirectoryFromBrowserPath(parent)
    }

    private func parentDirectoryPath(from path: String) -> String {
        if path == "~" || path == "/" {
            return path
        }
        if path.hasPrefix("~/") {
            let suffix = String(path.dropFirst(2))
            let components = suffix.split(separator: "/").dropLast()
            if components.isEmpty {
                return "~"
            }
            return "~/" + components.joined(separator: "/")
        }
        let components = path.split(separator: "/").dropLast()
        if components.isEmpty {
            return "/"
        }
        return "/" + components.joined(separator: "/")
    }

    private var machineSelectionBinding: Binding<String> {
        Binding(
            get: {
                viewModel.selectedMachineID ?? viewModel.machines.first?.id ?? ""
            },
            set: { newValue in
                Task {
                    await viewModel.selectMachine(
                        newValue,
                        serverURLString: serverURLString,
                        token: token
                    )
                }
            }
        )
    }

    private var agentSelectionBinding: Binding<APISessionSpawnAgent> {
        Binding(
            get: { viewModel.selectedAgent },
            set: { newValue in
                Task {
                    await viewModel.handleSelectedAgentChange(
                        newValue,
                        serverURLString: serverURLString,
                        token: token
                    )
                }
            }
        )
    }

    private var primaryActionTitle: String {
        hasResumeSelection ? "Resume Session" : "Start Session"
    }

    private var hasResumeSelection: Bool {
        selectedCodexResumeID != nil || selectedClaudeResumeID != nil
    }

    private var selectedCodexResumeID: String? {
        normalized(viewModel.codexResumeThreadID)
    }

    private var selectedClaudeResumeID: String? {
        normalized(viewModel.claudeResumeSessionID)
    }

    private var codexSelectionButtonTitle: String {
        if let id = selectedCodexResumeID {
            return "Codex Session: \(abbreviatedIdentifier(id))"
        }
        return "Choose Existing Codex Session"
    }

    private var claudeSelectionButtonTitle: String {
        if let id = selectedClaudeResumeID {
            return "Claude Session: \(abbreviatedIdentifier(id))"
        }
        return "Choose Existing Claude Session"
    }
}

private struct CodexThreadSelectionRow: View {
    let thread: APICodexThreadSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(thread.id)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let cwd = normalized(thread.cwd) {
                Text(cwd)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        normalized(thread.name) ?? "Untitled"
    }
}

private enum FocusedField: Hashable {
    case sessionToken
    case environmentVariables
    case directoryPath
    case directoryFilter
}

private struct ClaudeSessionSelectionRow: View {
    let session: APIClaudeSessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.id)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if let cwd = normalized(session.cwd) {
                Text(cwd)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let updatedAt = normalized(session.updatedAt) {
                Text(updatedAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

private func normalized(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func abbreviatedIdentifier(_ value: String) -> String {
    guard value.count > 16 else { return value }
    let prefix = value.prefix(8)
    let suffix = value.suffix(6)
    return "\(prefix)…\(suffix)"
}

#Preview {
    NewSessionView(
        serverURLString: "https://api.unhappy.im",
        token: "token",
        makeViewModel: {
            let service = URLSessionMachinesService()
            return NewSessionViewModel(
                machinesLoader: NewSessionMachinesLoadUseCase(service: service),
                directoryLister: NewSessionDirectoryListUseCase(service: service),
                spawner: NewSessionSpawnUseCase(service: service),
                recentProjectsManager: NewSessionNoopRecentProjectsManager(),
                profilesManager: NewSessionNoopProfilesManager(),
                modelsLoader: NewSessionModelsLoadUseCase(service: service),
                codexThreadsLoader: NewSessionCodexThreadsLoadUseCase(service: service),
                claudeSessionsLoader: NewSessionClaudeSessionsLoadUseCase(service: service)
            )
        }
    )
}
