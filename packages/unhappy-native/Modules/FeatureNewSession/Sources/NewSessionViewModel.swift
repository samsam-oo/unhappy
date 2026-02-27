import Foundation
import CoreKit

@MainActor
public final class NewSessionViewModel: ObservableObject {
    @Published public private(set) var machines: [APIMachine] = []
    @Published public private(set) var isLoadingMachines = false
    @Published public private(set) var isLoadingDirectory = false
    @Published public private(set) var isSpawning = false
    @Published public private(set) var directoryEntries: [APIMachineDirectoryEntry] = []
    @Published public private(set) var profiles: [NewSessionProfile] = []
    @Published public private(set) var recentProjects: [String] = []
    @Published public private(set) var selectedMachineID: String?
    @Published public var directoryPath: String = "~"
    @Published public var selectedAgent: APISessionSpawnAgent = .claude
    @Published public var codexResumeThreadID: String = ""
    @Published public var claudeResumeSessionID: String = ""
    @Published public var sessionToken: String = ""
    @Published public var selectedModel: String = ""
    @Published public var selectedReasoningEffort: NewSessionReasoningEffort = .auto
    @Published public var environmentVariablesText: String = ""
    @Published public private(set) var codexThreads: [APICodexThreadSummary] = []
    @Published public private(set) var availableModels: [String] = []
    @Published public private(set) var availableReasoningEfforts: [NewSessionReasoningEffort] = [.auto]
    @Published public private(set) var isLoadingModels = false
    @Published public private(set) var modelsErrorMessage: String?
    @Published public private(set) var isLoadingCodexThreads = false
    @Published public private(set) var isLoadingMoreCodexThreads = false
    @Published public private(set) var codexThreadsHasNext = false
    @Published public private(set) var codexThreadsErrorMessage: String?
    @Published public private(set) var claudeSessions: [APIClaudeSessionSummary] = []
    @Published public private(set) var isLoadingClaudeSessions = false
    @Published public private(set) var isLoadingMoreClaudeSessions = false
    @Published public private(set) var claudeSessionsHasNext = false
    @Published public private(set) var claudeSessionsErrorMessage: String?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var infoMessage: String?
    @Published public private(set) var approvalDirectory: String?
    @Published public private(set) var spawnedSessionID: String?

    private let machinesLoader: any NewSessionMachinesLoadingAction
    private let directoryLister: any NewSessionDirectoryListingAction
    private let spawner: any NewSessionSpawningAction
    private let recentProjectsManager: any NewSessionRecentProjectsManaging
    private let profilesManager: any NewSessionProfilesManaging
    private let modelsLoader: (any NewSessionModelsLoadingAction)?
    private let codexThreadsLoader: (any NewSessionCodexThreadsLoadingAction)?
    private let claudeSessionsLoader: (any NewSessionClaudeSessionsLoadingAction)?
    private var codexThreadsNextCursor: String?
    private var claudeSessionsNextCursor: String?
    private var selectedModelByAgent: [APISessionSpawnAgent: String] = [:]
    private var selectedReasoningEffortByAgent: [APISessionSpawnAgent: NewSessionReasoningEffort] = [:]
    private var lastSelectedAgent: APISessionSpawnAgent = .claude

    public init(
        machinesLoader: any NewSessionMachinesLoadingAction,
        directoryLister: any NewSessionDirectoryListingAction,
        spawner: any NewSessionSpawningAction,
        recentProjectsManager: any NewSessionRecentProjectsManaging,
        profilesManager: any NewSessionProfilesManaging,
        modelsLoader: (any NewSessionModelsLoadingAction)? = nil,
        codexThreadsLoader: (any NewSessionCodexThreadsLoadingAction)? = nil,
        claudeSessionsLoader: (any NewSessionClaudeSessionsLoadingAction)? = nil
    ) {
        self.machinesLoader = machinesLoader
        self.directoryLister = directoryLister
        self.spawner = spawner
        self.recentProjectsManager = recentProjectsManager
        self.profilesManager = profilesManager
        self.modelsLoader = modelsLoader
        self.codexThreadsLoader = codexThreadsLoader
        self.claudeSessionsLoader = claudeSessionsLoader
    }

    public func handleSelectedAgentChange(
        _ newAgent: APISessionSpawnAgent,
        serverURLString: String,
        token: String
    ) async {
        rememberCurrentAgentSelections()
        selectedAgent = newAgent
        selectedModel = selectedModelByAgent[newAgent] ?? ""
        selectedReasoningEffort = selectedReasoningEffortByAgent[newAgent] ?? .auto
        lastSelectedAgent = newAgent
        await loadModels(serverURLString: serverURLString, token: token, agent: newAgent)
    }

    public func setInitialSelectedAgent(_ agent: APISessionSpawnAgent) {
        selectedAgent = agent
        selectedModel = selectedModelByAgent[agent] ?? ""
        selectedReasoningEffort = selectedReasoningEffortByAgent[agent] ?? .auto
        lastSelectedAgent = agent
    }

    public func loadMachines(serverURLString: String, token: String) async {
        guard !isLoadingMachines else { return }
        isLoadingMachines = true
        errorMessage = nil
        defer { isLoadingMachines = false }

        recentProjects = await recentProjectsManager.loadRecentProjects()
        profiles = await profilesManager.loadProfiles()

        do {
            let loaded = try await machinesLoader.loadMachines(
                serverURLString: serverURLString,
                token: token
            )
            machines = loaded
            if selectedMachineID == nil {
                selectedMachineID = loaded.first?.id
            } else if let selectedMachineID, loaded.contains(where: { $0.id == selectedMachineID }) == false {
                self.selectedMachineID = loaded.first?.id
            }

            if self.selectedMachineID != nil {
                // Keep machine-loading UI scoped to machine fetch, not directory fetch.
                isLoadingMachines = false
                await loadDirectory(serverURLString: serverURLString, token: token)
                await loadModels(serverURLString: serverURLString, token: token, agent: selectedAgent)
            } else {
                directoryEntries = []
                availableModels = []
                availableReasoningEfforts = [.auto]
                modelsErrorMessage = nil
            }
        } catch {
            machines = []
            directoryEntries = []
            availableModels = []
            availableReasoningEfforts = [.auto]
            modelsErrorMessage = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func selectMachine(
        _ machineID: String,
        serverURLString: String,
        token: String
    ) async {
        selectedMachineID = machineID
        codexThreads = []
        codexThreadsNextCursor = nil
        codexThreadsHasNext = false
        isLoadingMoreCodexThreads = false
        codexThreadsErrorMessage = nil
        claudeSessions = []
        claudeSessionsNextCursor = nil
        claudeSessionsHasNext = false
        isLoadingMoreClaudeSessions = false
        claudeSessionsErrorMessage = nil
        availableModels = []
        availableReasoningEfforts = [.auto]
        modelsErrorMessage = nil
        approvalDirectory = nil
        spawnedSessionID = nil
        infoMessage = nil
        await loadDirectory(serverURLString: serverURLString, token: token)
        await loadModels(serverURLString: serverURLString, token: token, agent: selectedAgent)
    }

    public func loadModels(
        serverURLString: String,
        token: String,
        agent: APISessionSpawnAgent? = nil
    ) async {
        guard !isLoadingModels else { return }
        guard let machineID = selectedMachineID else {
            availableModels = []
            availableReasoningEfforts = [.auto]
            modelsErrorMessage = NewSessionError.missingMachineID.errorDescription
            return
        }

        let targetAgent = agent ?? selectedAgent
        guard let modelsLoader else {
            availableModels = []
            availableReasoningEfforts = [.auto]
            modelsErrorMessage = nil
            return
        }

        if targetAgent == selectedAgent {
            rememberCurrentAgentSelections()
        }

        isLoadingModels = true
        modelsErrorMessage = nil
        defer { isLoadingModels = false }

        do {
            let capabilities = try await modelsLoader.loadModels(
                serverURLString: serverURLString,
                token: token,
                machineID: machineID,
                agent: targetAgent
            )
            let models = capabilities.models
            let reasoningEfforts = normalizeReasoningEfforts(capabilities.reasoningEfforts)
            availableModels = models
            availableReasoningEfforts = reasoningEfforts
            modelsErrorMessage = nil

            let selected = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !selected.isEmpty, !models.contains(selected) {
                selectedModel = ""
            }

            if !reasoningEfforts.contains(selectedReasoningEffort) {
                selectedReasoningEffort = reasoningEfforts.first ?? .auto
            }

            selectedModelByAgent[targetAgent] = selectedModel
            selectedReasoningEffortByAgent[targetAgent] = selectedReasoningEffort
        } catch {
            availableModels = []
            availableReasoningEfforts = [.auto]
            modelsErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func loadDirectory(
        serverURLString: String,
        token: String,
        attemptRecoveryOnMissingMachine: Bool = true
    ) async {
        guard let machineID = selectedMachineID else {
            directoryEntries = []
            return
        }

        let path = normalizedPath(directoryPath)
        directoryPath = path
        isLoadingDirectory = true
        errorMessage = nil
        defer { isLoadingDirectory = false }

        do {
            directoryEntries = try await directoryLister.listDirectory(
                serverURLString: serverURLString,
                token: token,
                machineID: machineID,
                path: path
            )
            errorMessage = nil
        } catch let apiError as MachinesAPIError {
            if case .endpointUnavailable(let endpoint) = apiError {
                directoryEntries = []
                errorMessage = "Folder browse API is not deployed on this server (\(endpoint)). Backend update is required."
                return
            }
            if case .invalidHTTPStatus(404) = apiError, attemptRecoveryOnMissingMachine {
                await recoverFromMissingMachine(
                    serverURLString: serverURLString,
                    token: token
                )
                return
            }
            directoryEntries = []
            errorMessage = apiError.errorDescription ?? apiError.localizedDescription
        } catch let sessionError as NewSessionError {
            let description = sessionError.errorDescription ?? sessionError.localizedDescription
            if attemptRecoveryOnMissingMachine && isHTTP404Message(description) {
                await recoverFromMissingMachine(
                    serverURLString: serverURLString,
                    token: token
                )
                return
            }
            directoryEntries = []
            errorMessage = description
        } catch {
            let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if attemptRecoveryOnMissingMachine && isHTTP404Message(description) {
                await recoverFromMissingMachine(
                    serverURLString: serverURLString,
                    token: token
                )
                return
            }
            directoryEntries = []
            errorMessage = description
        }
    }

    public func loadCodexThreads(serverURLString: String, token: String, limit: Int = 20) async {
        guard let machineID = selectedMachineID else {
            codexThreads = []
            codexThreadsNextCursor = nil
            codexThreadsHasNext = false
            codexThreadsErrorMessage = NewSessionError.missingMachineID.errorDescription
            return
        }

        isLoadingCodexThreads = true
        isLoadingMoreCodexThreads = false
        codexThreads = []
        codexThreadsNextCursor = nil
        codexThreadsHasNext = false
        codexThreadsErrorMessage = nil
        defer { isLoadingCodexThreads = false }

        guard let codexThreadsLoader else {
            codexThreadsErrorMessage = "Codex session listing is unavailable in this build"
            return
        }

        do {
            let page = try await codexThreadsLoader.loadCodexThreads(
                serverURLString: serverURLString,
                token: token,
                machineID: machineID,
                limit: limit,
                cwd: normalizedPath(directoryPath),
                cursor: nil
            )
            codexThreads = page.threads
            let metadata = paginationMetadata(nextCursor: page.nextCursor, hasNext: page.hasNext)
            codexThreadsNextCursor = metadata.nextCursor
            codexThreadsHasNext = metadata.hasNext
            codexThreadsErrorMessage = nil
        } catch {
            codexThreads = []
            codexThreadsNextCursor = nil
            codexThreadsHasNext = false
            codexThreadsErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func loadClaudeSessions(serverURLString: String, token: String, limit: Int = 20) async {
        guard let machineID = selectedMachineID else {
            claudeSessions = []
            claudeSessionsNextCursor = nil
            claudeSessionsHasNext = false
            claudeSessionsErrorMessage = NewSessionError.missingMachineID.errorDescription
            return
        }

        isLoadingClaudeSessions = true
        isLoadingMoreClaudeSessions = false
        claudeSessions = []
        claudeSessionsNextCursor = nil
        claudeSessionsHasNext = false
        claudeSessionsErrorMessage = nil
        defer { isLoadingClaudeSessions = false }

        guard let claudeSessionsLoader else {
            claudeSessionsErrorMessage = "Claude session listing is unavailable in this build"
            return
        }

        do {
            let page = try await claudeSessionsLoader.loadClaudeSessions(
                serverURLString: serverURLString,
                token: token,
                machineID: machineID,
                limit: limit,
                cwd: normalizedPath(directoryPath),
                cursor: nil
            )
            claudeSessions = page.sessions
            let metadata = paginationMetadata(nextCursor: page.nextCursor, hasNext: page.hasNext)
            claudeSessionsNextCursor = metadata.nextCursor
            claudeSessionsHasNext = metadata.hasNext
            claudeSessionsErrorMessage = nil
        } catch {
            claudeSessions = []
            claudeSessionsNextCursor = nil
            claudeSessionsHasNext = false
            claudeSessionsErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func loadMoreCodexThreads(serverURLString: String, token: String, limit: Int = 20) async {
        guard !isLoadingCodexThreads else { return }
        guard !isLoadingMoreCodexThreads else { return }
        guard let machineID = selectedMachineID else {
            codexThreadsErrorMessage = NewSessionError.missingMachineID.errorDescription
            return
        }
        guard codexThreadsHasNext, let cursor = codexThreadsNextCursor else {
            codexThreadsHasNext = false
            codexThreadsNextCursor = nil
            return
        }
        guard let codexThreadsLoader else {
            codexThreadsErrorMessage = "Codex session listing is unavailable in this build"
            return
        }

        isLoadingMoreCodexThreads = true
        defer { isLoadingMoreCodexThreads = false }

        do {
            let page = try await codexThreadsLoader.loadCodexThreads(
                serverURLString: serverURLString,
                token: token,
                machineID: machineID,
                limit: limit,
                cwd: normalizedPath(directoryPath),
                cursor: cursor
            )
            codexThreads = mergeUniqueByID(existing: codexThreads, incoming: page.threads)
            let metadata = paginationMetadata(nextCursor: page.nextCursor, hasNext: page.hasNext)
            codexThreadsNextCursor = metadata.nextCursor
            codexThreadsHasNext = metadata.hasNext
            codexThreadsErrorMessage = nil
        } catch {
            codexThreadsErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func loadMoreClaudeSessions(serverURLString: String, token: String, limit: Int = 20) async {
        guard !isLoadingClaudeSessions else { return }
        guard !isLoadingMoreClaudeSessions else { return }
        guard let machineID = selectedMachineID else {
            claudeSessionsErrorMessage = NewSessionError.missingMachineID.errorDescription
            return
        }
        guard claudeSessionsHasNext, let cursor = claudeSessionsNextCursor else {
            claudeSessionsHasNext = false
            claudeSessionsNextCursor = nil
            return
        }
        guard let claudeSessionsLoader else {
            claudeSessionsErrorMessage = "Claude session listing is unavailable in this build"
            return
        }

        isLoadingMoreClaudeSessions = true
        defer { isLoadingMoreClaudeSessions = false }

        do {
            let page = try await claudeSessionsLoader.loadClaudeSessions(
                serverURLString: serverURLString,
                token: token,
                machineID: machineID,
                limit: limit,
                cwd: normalizedPath(directoryPath),
                cursor: cursor
            )
            claudeSessions = mergeUniqueByID(existing: claudeSessions, incoming: page.sessions)
            let metadata = paginationMetadata(nextCursor: page.nextCursor, hasNext: page.hasNext)
            claudeSessionsNextCursor = metadata.nextCursor
            claudeSessionsHasNext = metadata.hasNext
            claudeSessionsErrorMessage = nil
        } catch {
            claudeSessionsErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func selectCodexThread(_ thread: APICodexThreadSummary) {
        rememberCurrentAgentSelections()
        codexResumeThreadID = thread.id
        claudeResumeSessionID = ""
        selectedAgent = .codex
        selectedModel = selectedModelByAgent[.codex] ?? ""
        selectedReasoningEffort = selectedReasoningEffortByAgent[.codex] ?? .auto
        lastSelectedAgent = .codex
        if let threadCWD = normalizedOptionalPath(thread.cwd) {
            directoryPath = normalizedPath(threadCWD)
        }
        selectedModel = normalizedOptionalPath(thread.model) ?? ""
        selectedReasoningEffort = NewSessionReasoningEffort(threadEffort: thread.effort)
        selectedModelByAgent[.codex] = selectedModel
        selectedReasoningEffortByAgent[.codex] = selectedReasoningEffort
        infoMessage = "Selected Codex session \(thread.id)"
        errorMessage = nil
    }

    public func selectClaudeSession(_ session: APIClaudeSessionSummary) {
        rememberCurrentAgentSelections()
        claudeResumeSessionID = session.id
        codexResumeThreadID = ""
        selectedAgent = .claude
        selectedModel = selectedModelByAgent[.claude] ?? ""
        selectedReasoningEffort = selectedReasoningEffortByAgent[.claude] ?? .auto
        lastSelectedAgent = .claude
        if let sessionCWD = normalizedOptionalPath(session.cwd) {
            directoryPath = normalizedPath(sessionCWD)
        }
        infoMessage = "Selected Claude session \(session.id)"
        errorMessage = nil
    }

    public func clearCodexSelection() {
        codexResumeThreadID = ""
        if infoMessage?.contains("Selected Codex session") == true {
            infoMessage = nil
        }
    }

    public func clearClaudeSelection() {
        claudeResumeSessionID = ""
        if infoMessage?.contains("Selected Claude session") == true {
            infoMessage = nil
        }
    }

    public func selectDirectoryEntry(
        _ entry: APIMachineDirectoryEntry,
        serverURLString: String,
        token: String
    ) async {
        guard entry.type == "directory" else { return }
        directoryPath = resolvedPath(current: directoryPath, entryName: entry.name)
        await loadDirectory(serverURLString: serverURLString, token: token)
    }

    public func selectRecentProject(
        _ path: String,
        serverURLString: String,
        token: String
    ) async {
        directoryPath = path
        await loadDirectory(serverURLString: serverURLString, token: token)
    }

    public func applyProfile(
        id: String,
        serverURLString: String,
        token: String
    ) async {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }

        if let machineID = profile.machineID, machines.contains(where: { $0.id == machineID }) {
            selectedMachineID = machineID
        }
        directoryPath = normalizedPath(profile.directoryPath)
        selectedAgent = profile.agent
        lastSelectedAgent = profile.agent
        codexResumeThreadID = profile.codexResumeThreadID ?? ""
        claudeResumeSessionID = profile.claudeResumeSessionID ?? ""
        sessionToken = profile.sessionToken ?? ""
        selectedModel = profile.model ?? ""
        selectedReasoningEffort = NewSessionReasoningEffort(threadEffort: profile.reasoningEffort)
        selectedModelByAgent[profile.agent] = selectedModel
        selectedReasoningEffortByAgent[profile.agent] = selectedReasoningEffort
        environmentVariablesText = profile.environmentVariablesText
        await loadDirectory(serverURLString: serverURLString, token: token)
        await loadModels(serverURLString: serverURLString, token: token, agent: selectedAgent)
    }

    public func saveCurrentAsProfile(named name: String) async {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return }
        rememberCurrentAgentSelections()

        let profile = NewSessionProfile(
            id: UUID().uuidString.lowercased(),
            name: normalizedName,
            machineID: selectedMachineID,
            directoryPath: normalizedPath(directoryPath),
            agent: selectedAgent,
            codexResumeThreadID: normalizedOptionalPath(codexResumeThreadID),
            claudeResumeSessionID: normalizedOptionalPath(claudeResumeSessionID),
            sessionToken: normalizedOptionalPath(sessionToken),
            model: normalizedOptionalPath(selectedModel),
            reasoningEffort: selectedReasoningEffort.apiValue,
            environmentVariablesText: environmentVariablesText
        )
        profiles = await profilesManager.saveProfile(profile)
    }

    public func deleteProfile(id: String) async {
        profiles = await profilesManager.deleteProfile(id: id)
    }

    public func startSession(serverURLString: String, token: String) async -> Bool {
        await spawn(
            serverURLString: serverURLString,
            token: token,
            directory: directoryPath,
            approvedNewDirectoryCreation: false
        )
    }

    public func continueWithDirectoryApproval(serverURLString: String, token: String) async -> Bool {
        guard let approvalDirectory else { return false }
        return await spawn(
            serverURLString: serverURLString,
            token: token,
            directory: approvalDirectory,
            approvedNewDirectoryCreation: true
        )
    }

    private func spawn(
        serverURLString: String,
        token: String,
        directory: String,
        approvedNewDirectoryCreation: Bool
    ) async -> Bool {
        rememberCurrentAgentSelections()
        let environmentVariables: [String: String]
        do {
            environmentVariables = try NewSessionEnvironmentVariablesParser.parse(environmentVariablesText)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }

        guard let machineID = selectedMachineID else {
            errorMessage = NewSessionError.missingMachineID.errorDescription
            return false
        }

        isSpawning = true
        errorMessage = nil
        infoMessage = nil
        spawnedSessionID = nil
        if approvedNewDirectoryCreation {
            approvalDirectory = nil
        }
        defer { isSpawning = false }

        do {
            let result = try await spawner.spawnSession(
                serverURLString: serverURLString,
                token: token,
                machineID: machineID,
                directory: directory,
                agent: selectedAgent,
                approvedNewDirectoryCreation: approvedNewDirectoryCreation,
                codexResumeThreadID: codexResumeThreadID,
                claudeResumeSessionID: claudeResumeSessionID,
                sessionToken: sessionToken,
                environmentVariables: environmentVariables,
                model: selectedModel,
                reasoningEffort: selectedReasoningEffort.apiValue
            )
            let sessionID = result.sessionID?.trimmingCharacters(in: .whitespacesAndNewlines)
            spawnedSessionID = (sessionID?.isEmpty == false) ? sessionID : nil
            if let spawnedSessionID {
                infoMessage = "Spawned session \(spawnedSessionID)"
            } else {
                infoMessage = "Spawned session"
            }
            recentProjects = await recentProjectsManager.recordRecentProject(normalizedPath(directory))
            approvalDirectory = nil
            errorMessage = nil
            return true
        } catch let error as NewSessionError {
            if case .requiresUserApproval(let directory) = error {
                approvalDirectory = normalizedOptionalPath(directory)
                errorMessage = nil
                infoMessage = nil
                return false
            }
            approvalDirectory = nil
            infoMessage = nil
            errorMessage = error.errorDescription ?? "Failed to spawn session"
            return false
        } catch {
            approvalDirectory = nil
            infoMessage = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private func recoverFromMissingMachine(serverURLString: String, token: String) async {
        do {
            let loaded = try await machinesLoader.loadMachines(
                serverURLString: serverURLString,
                token: token
            )
            machines = loaded

            guard !loaded.isEmpty else {
                selectedMachineID = nil
                directoryEntries = []
                errorMessage = "No machines available. Connect or refresh your daemon first."
                return
            }

            if let selectedMachineID, loaded.contains(where: { $0.id == selectedMachineID }) {
                await loadDirectory(
                    serverURLString: serverURLString,
                    token: token,
                    attemptRecoveryOnMissingMachine: false
                )
                return
            }

            selectedMachineID = loaded.first?.id
            await loadDirectory(
                serverURLString: serverURLString,
                token: token,
                attemptRecoveryOnMissingMachine: false
            )
        } catch {
            directoryEntries = []
            errorMessage = "Folder list failed (404). Machine list refresh also failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    private func isHTTP404Message(_ message: String) -> Bool {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        if normalized.contains("status 404") {
            return true
        }
        if normalized.contains("http 404") {
            return true
        }
        if normalized == "404" {
            return true
        }
        return false
    }

    private func rememberCurrentAgentSelections() {
        selectedModelByAgent[lastSelectedAgent] = selectedModel
        selectedReasoningEffortByAgent[lastSelectedAgent] = selectedReasoningEffort
    }
}


private struct CursorPaginationMetadata {
    let nextCursor: String?
    let hasNext: Bool
}

private func paginationMetadata(nextCursor: String?, hasNext: Bool) -> CursorPaginationMetadata {
    let normalizedCursor = normalizedOptionalPath(nextCursor)
    return CursorPaginationMetadata(
        nextCursor: normalizedCursor,
        hasNext: hasNext && normalizedCursor != nil
    )
}

private func mergeUniqueByID<Row: Identifiable>(
    existing: [Row],
    incoming: [Row]
) -> [Row] where Row.ID == String {
    var merged = existing
    var seenIDs = Set(existing.map(\.id))
    for row in incoming where seenIDs.insert(row.id).inserted {
        merged.append(row)
    }
    return merged
}

private func normalizeReasoningEfforts(_ rawValues: [String]) -> [NewSessionReasoningEffort] {
    var normalized: [NewSessionReasoningEffort] = [.auto]
    var seen: Set<NewSessionReasoningEffort> = [.auto]

    for raw in rawValues {
        guard let value = NewSessionReasoningEffort.fromBackend(raw) else { continue }
        if seen.insert(value).inserted {
            normalized.append(value)
        }
    }

    return normalized
}

private func normalizedPath(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "~" : trimmed
}

private func normalizedOptionalPath(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func resolvedPath(current: String, entryName: String) -> String {
    let path = normalizedPath(current)
    let trimmedName = entryName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { return path }
    if trimmedName == "." {
        return path
    }
    if trimmedName == ".." {
        if path == "~" {
            return "~"
        }
        if path.hasPrefix("~/") {
            let suffix = String(path.dropFirst(2))
            let components = suffix.split(separator: "/").dropLast()
            if components.isEmpty {
                return "~"
            }
            return "~/" + components.joined(separator: "/")
        }
        if path == "/" {
            return "/"
        }
        let components = path.split(separator: "/").dropLast()
        if components.isEmpty {
            return "/"
        }
        return "/" + components.joined(separator: "/")
    }
    if trimmedName.hasPrefix("/") {
        return trimmedName
    }
    if path == "/" {
        return "/" + trimmedName
    }
    if path.hasSuffix("/") {
        return path + trimmedName
    }
    if path == "~" {
        return "~/" + trimmedName
    }
    return path + "/" + trimmedName
}
