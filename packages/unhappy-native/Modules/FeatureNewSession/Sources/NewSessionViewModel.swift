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
    @Published public var environmentVariablesText: String = ""
    @Published public private(set) var codexThreads: [APICodexThreadSummary] = []
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
    private let codexThreadsLoader: (any NewSessionCodexThreadsLoadingAction)?
    private let claudeSessionsLoader: (any NewSessionClaudeSessionsLoadingAction)?
    private var codexThreadsNextCursor: String?
    private var claudeSessionsNextCursor: String?

    public init(
        machinesLoader: any NewSessionMachinesLoadingAction,
        directoryLister: any NewSessionDirectoryListingAction,
        spawner: any NewSessionSpawningAction,
        recentProjectsManager: any NewSessionRecentProjectsManaging,
        profilesManager: any NewSessionProfilesManaging,
        codexThreadsLoader: (any NewSessionCodexThreadsLoadingAction)? = nil,
        claudeSessionsLoader: (any NewSessionClaudeSessionsLoadingAction)? = nil
    ) {
        self.machinesLoader = machinesLoader
        self.directoryLister = directoryLister
        self.spawner = spawner
        self.recentProjectsManager = recentProjectsManager
        self.profilesManager = profilesManager
        self.codexThreadsLoader = codexThreadsLoader
        self.claudeSessionsLoader = claudeSessionsLoader
    }

    public func loadMachines(serverURLString: String, token: String) async {
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
                await loadDirectory(serverURLString: serverURLString, token: token)
            } else {
                directoryEntries = []
            }
        } catch {
            machines = []
            directoryEntries = []
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
        approvalDirectory = nil
        spawnedSessionID = nil
        infoMessage = nil
        await loadDirectory(serverURLString: serverURLString, token: token)
    }

    public func loadDirectory(serverURLString: String, token: String) async {
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
        } catch {
            directoryEntries = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
        codexResumeThreadID = thread.id
        claudeResumeSessionID = ""
        selectedAgent = .codex
    }

    public func selectClaudeSession(_ session: APIClaudeSessionSummary) {
        claudeResumeSessionID = session.id
        codexResumeThreadID = ""
        selectedAgent = .claude
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
        codexResumeThreadID = profile.codexResumeThreadID ?? ""
        claudeResumeSessionID = profile.claudeResumeSessionID ?? ""
        sessionToken = profile.sessionToken ?? ""
        environmentVariablesText = profile.environmentVariablesText
        await loadDirectory(serverURLString: serverURLString, token: token)
    }

    public func saveCurrentAsProfile(named name: String) async {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return }

        let profile = NewSessionProfile(
            id: UUID().uuidString.lowercased(),
            name: normalizedName,
            machineID: selectedMachineID,
            directoryPath: normalizedPath(directoryPath),
            agent: selectedAgent,
            codexResumeThreadID: normalizedOptionalPath(codexResumeThreadID),
            claudeResumeSessionID: normalizedOptionalPath(claudeResumeSessionID),
            sessionToken: normalizedOptionalPath(sessionToken),
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
                environmentVariables: environmentVariables
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
