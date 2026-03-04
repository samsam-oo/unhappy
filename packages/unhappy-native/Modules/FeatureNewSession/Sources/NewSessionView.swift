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
                machineSection
                directorySection
                profilesSection
                agentSection
                advancedSection
                actionSection
                statusSection
            }
            .scrollDismissesKeyboard(.interactively)
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
                NewSessionCodexSessionsSheet(
                    viewModel: viewModel,
                    serverURLString: serverURLString,
                    token: token,
                    onClose: { showCodexThreadsSheet = false }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showDirectoryBrowserSheet) {
                NewSessionDirectoryBrowserSheet(
                    viewModel: viewModel,
                    serverURLString: serverURLString,
                    token: token,
                    isPresented: $showDirectoryBrowserSheet,
                    directoryBrowserFilterText: $directoryBrowserFilterText,
                    directoryBrowserPathDraft: $directoryBrowserPathDraft,
                    focusedField: $focusedField,
                    filteredDirectoryBrowserEntries: filteredDirectoryBrowserEntries,
                    directoryEntryFullPath: directoryEntryFullPath,
                    loadDirectoryFromBrowserPath: { path in
                        await loadDirectoryFromBrowserPath(path)
                    },
                    goToParentDirectoryFromBrowser: {
                        await goToParentDirectoryFromBrowser()
                    }
                )
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showClaudeSessionsSheet) {
                NewSessionClaudeSessionsSheet(
                    viewModel: viewModel,
                    serverURLString: serverURLString,
                    token: token,
                    onClose: { showClaudeSessionsSheet = false }
                )
                .presentationDetents([.medium, .large])
            }
            .task(id: "\(serverURLString)|\(token)") {
                viewModel.setInitialSelectedAgent(defaultAgent)
                await viewModel.loadMachines(serverURLString: serverURLString, token: token)
            }
        }
    }

    private var machineSection: some View {
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
    }

    private var directorySection: some View {
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
            .disabled(viewModel.selectedMachineID == nil)

            if viewModel.isLoadingDirectory {
                HStack {
                    ProgressView()
                    Text("Loading directory…")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var profilesSection: some View {
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
    }

    private var agentSection: some View {
        Section("Agent") {
            Picker("Agent", selection: agentSelectionBinding) {
                Text("Claude").tag(APISessionSpawnAgent.claude)
                Text("Codex").tag(APISessionSpawnAgent.codex)
                Text("Gemini").tag(APISessionSpawnAgent.gemini)
            }
        }
    }

    private var advancedSection: some View {
        Section("Advanced") {
            if viewModel.isLoadingModels {
                HStack {
                    ProgressView()
                    Text("Loading models…")
                        .foregroundStyle(.secondary)
                }
            }

            Menu {
                Button("Default") {
                    viewModel.setSelectedModel("")
                }
                ForEach(viewModel.availableModels, id: \.self) { model in
                    Button(model) {
                        viewModel.setSelectedModel(model)
                    }
                }
            } label: {
                HStack {
                    Text("Model")
                    Spacer()
                    Text(selectedModelDisplayValue)
                        .foregroundStyle(.secondary)
                }
            }

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

            Menu {
                ForEach(viewModel.availableReasoningEfforts, id: \.rawValue) { value in
                    Button(value.displayName) {
                        viewModel.setSelectedReasoningEffort(value)
                    }
                }
            } label: {
                HStack {
                    Text("Reasoning Effort")
                    Spacer()
                    Text(viewModel.selectedReasoningEffort.displayName)
                        .foregroundStyle(.secondary)
                }
            }

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
    }

    private var actionSection: some View {
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
    }

    @ViewBuilder
    private var statusSection: some View {
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

    private var selectedModelDisplayValue: String {
        let normalized = viewModel.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "Default" : normalized
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

enum FocusedField: Hashable {
    case sessionToken
    case environmentVariables
    case directoryPath
    case directoryFilter
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
