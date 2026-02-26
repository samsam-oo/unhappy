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
    @State private var directoryFilterText = ""

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
                                Text(machine.id).tag(machine.id)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }

                Section("Directory") {
                    TextField("Path", text: $viewModel.directoryPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Text("Selected directory: \(viewModel.directoryPath)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    TextField("Filter current directory entries", text: $directoryFilterText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !viewModel.recentProjects.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recent Projects")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(viewModel.recentProjects, id: \.self) { projectPath in
                                Button {
                                    Task {
                                        await viewModel.selectRecentProject(
                                            projectPath,
                                            serverURLString: serverURLString,
                                            token: token
                                        )
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "folder")
                                            .foregroundStyle(.secondary)
                                        Text(projectPath)
                                            .font(.footnote.monospaced())
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button("Browse Directory") {
                        Task {
                            await viewModel.loadDirectory(
                                serverURLString: serverURLString,
                                token: token
                            )
                        }
                    }
                    .disabled(viewModel.selectedMachineID == nil || viewModel.isLoadingDirectory)

                    if viewModel.isLoadingDirectory {
                        HStack {
                            ProgressView()
                            Text("Loading directory…")
                                .foregroundStyle(.secondary)
                        }
                    } else if !viewModel.directoryEntries.isEmpty {
                        if filteredDirectoryEntries.isEmpty {
                            Text("No entries match the current filter")
                                .foregroundStyle(.secondary)
                        }

                        ForEach(filteredDirectoryEntries) { entry in
                            Button {
                                Task {
                                    await viewModel.selectDirectoryEntry(
                                        entry,
                                        serverURLString: serverURLString,
                                        token: token
                                    )
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: entry.type == "directory" ? "folder" : "doc.text")
                                        .foregroundStyle(entry.type == "directory" ? Color.accentColor : Color.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name)
                                            .lineLimit(1)
                                        Text(entry.type.capitalized)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if entry.type == "directory" {
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(entry.type != "directory")
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
                    Picker("Agent", selection: $viewModel.selectedAgent) {
                        Text("Claude").tag(APISessionSpawnAgent.claude)
                        Text("Codex").tag(APISessionSpawnAgent.codex)
                        Text("Gemini").tag(APISessionSpawnAgent.gemini)
                    }
                }

                Section("Advanced") {
                    TextField("Codex resume thread ID (optional)", text: $viewModel.codexResumeThreadID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(viewModel.isLoadingCodexThreads ? "Loading Codex Sessions…" : "Choose Existing Codex Session") {
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

                    TextField("Claude resume session ID (optional)", text: $viewModel.claudeResumeSessionID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(viewModel.isLoadingClaudeSessions ? "Loading Claude Sessions…" : "Choose Existing Claude Session") {
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

                    TextField("Session token (optional)", text: $viewModel.sessionToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Environment Variables (KEY=VALUE)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $viewModel.environmentVariablesText)
                            .font(.footnote.monospaced())
                            .frame(minHeight: 96)
                        Text("One variable per line. Empty lines and # comments are ignored.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Action") {
                    Button(viewModel.isSpawning ? "Starting…" : "Start Session") {
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
                viewModel.selectedAgent = defaultAgent
                await viewModel.loadMachines(serverURLString: serverURLString, token: token)
            }
        }
    }

    private var filteredDirectoryEntries: [APIMachineDirectoryEntry] {
        let trimmedFilter = directoryFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFilter.isEmpty else {
            return viewModel.directoryEntries
        }
        return viewModel.directoryEntries.filter { entry in
            entry.name.localizedCaseInsensitiveContains(trimmedFilter)
        }
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
                codexThreadsLoader: NewSessionCodexThreadsLoadUseCase(service: service),
                claudeSessionsLoader: NewSessionClaudeSessionsLoadUseCase(service: service)
            )
        }
    )
}
