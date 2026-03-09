import Foundation
import CoreKit

public protocol NewSessionMachinesLoadingAction: Sendable {
    func loadMachines(serverURLString: String, token: String) async throws -> [APIMachine]
}

public protocol NewSessionDirectoryListingAction: Sendable {
    func listDirectory(
        serverURLString: String,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> [APIMachineDirectoryEntry]
}

public protocol NewSessionSpawningAction: Sendable {
    func spawnSession(_ request: NewSessionSpawnRequest) async throws -> APISessionSpawnResult
}

public struct NewSessionSpawnRequest: Sendable, Equatable {
    public let serverURLString: String
    public let token: String
    public let machineID: String
    public let wrappedMachineDataEncryptionKey: String?
    public let directory: String
    public let agent: APISessionSpawnAgent
    public let approvedNewDirectoryCreation: Bool
    public let codexResumeThreadID: String?
    public let claudeResumeSessionID: String?
    public let sessionToken: String?
    public let environmentVariables: [String: String]
    public let model: String?
    public let reasoningEffort: APISessionReasoningEffort?

    public init(
        serverURLString: String,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String? = nil,
        directory: String,
        agent: APISessionSpawnAgent,
        approvedNewDirectoryCreation: Bool,
        codexResumeThreadID: String?,
        claudeResumeSessionID: String?,
        sessionToken: String?,
        environmentVariables: [String: String],
        model: String?,
        reasoningEffort: APISessionReasoningEffort?
    ) {
        self.serverURLString = serverURLString
        self.token = token
        self.machineID = machineID
        self.wrappedMachineDataEncryptionKey = wrappedMachineDataEncryptionKey
        self.directory = directory
        self.agent = agent
        self.approvedNewDirectoryCreation = approvedNewDirectoryCreation
        self.codexResumeThreadID = codexResumeThreadID
        self.claudeResumeSessionID = claudeResumeSessionID
        self.sessionToken = sessionToken
        self.environmentVariables = environmentVariables
        self.model = model
        self.reasoningEffort = reasoningEffort
    }
}

public protocol NewSessionModelsLoadingAction: Sendable {
    func loadModels(
        serverURLString: String,
        token: String,
        machineID: String,
        agent: APISessionSpawnAgent
    ) async throws -> APIMachineAgentCapabilities
}

public protocol NewSessionCodexThreadsLoadingAction: Sendable {
    func loadCodexThreads(
        serverURLString: String,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APICodexThreadsPage
}

public protocol NewSessionClaudeSessionsLoadingAction: Sendable {
    func loadClaudeSessions(
        serverURLString: String,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APIClaudeSessionsPage
}

public protocol NewSessionRecentProjectsManaging: Sendable {
    func loadRecentProjects() async -> [String]
    func recordRecentProject(_ path: String) async -> [String]
}

public actor NewSessionNoopRecentProjectsManager: NewSessionRecentProjectsManaging {
    public init() {}

    public func loadRecentProjects() async -> [String] { [] }

    public func recordRecentProject(_ path: String) async -> [String] { [] }
}

public enum NewSessionError: LocalizedError, Equatable {
    case missingToken
    case invalidServerURL
    case missingMachineID
    case missingDirectory
    case invalidEnvironmentVariable(line: Int, value: String)
    case requiresUserApproval(directory: String?)
    case failed(message: String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .invalidServerURL:
            return "Invalid server URL"
        case .missingMachineID:
            return "Machine ID is required"
        case .missingDirectory:
            return "Directory is required"
        case .invalidEnvironmentVariable(let line, let value):
            return "Invalid environment variable at line \(line): \(value)"
        case .requiresUserApproval(let directory):
            if let directory, !directory.isEmpty {
                return "Directory creation approval is required: \(directory)"
            }
            return "Directory creation approval is required"
        case .failed(let message):
            return message
        }
    }
}

private struct NormalizedNewSessionInputs {
    let serverURL: URL
    let token: String
    let machineID: String
    let directory: String
}

public actor NewSessionMachinesLoadUseCase: NewSessionMachinesLoadingAction {
    private let service: any MachinesFetching

    public init(service: any MachinesFetching) {
        self.service = service
    }

    public func loadMachines(serverURLString: String, token: String) async throws -> [APIMachine] {
        let normalizedInputs = try normalizeInputs(
            serverURLString: serverURLString,
            token: token,
            machineID: nil,
            directory: nil
        )
        let rows = try await service.fetchMachines(
            serverURL: normalizedInputs.serverURL,
            token: normalizedInputs.token
        )
        return rows
            .filter(\.active)
            .sorted { lhs, rhs in
            if lhs.activeAt != rhs.activeAt {
                return lhs.activeAt > rhs.activeAt
            }
            return lhs.updatedAt > rhs.updatedAt
            }
    }
}

public actor NewSessionDirectoryListUseCase: NewSessionDirectoryListingAction {
    private let service: any MachineDirectoryListing

    public init(service: any MachineDirectoryListing) {
        self.service = service
    }

    public func listDirectory(
        serverURLString: String,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> [APIMachineDirectoryEntry] {
        let normalizedInputs = try normalizeInputs(
            serverURLString: serverURLString,
            token: token,
            machineID: machineID,
            directory: path
        )
        let result = try await service.listDirectory(
            serverURL: normalizedInputs.serverURL,
            token: normalizedInputs.token,
            machineID: normalizedInputs.machineID,
            path: normalizedInputs.directory,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey
        )
        if !result.success {
            let normalizedError = result.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NewSessionError.failed(
                message: (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "Failed to list directory"
            )
        }
        let entries = result.entries ?? []
        return entries.sorted { lhs, rhs in
            if lhs.type != rhs.type {
                return lhs.type == "directory"
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

public actor NewSessionSpawnUseCase: NewSessionSpawningAction {
    private let service: any MachineSessionSpawning

    public init(service: any MachineSessionSpawning) {
        self.service = service
    }

    public func spawnSession(_ request: NewSessionSpawnRequest) async throws -> APISessionSpawnResult {
        let normalizedInputs = try normalizeInputs(
            serverURLString: request.serverURLString,
            token: request.token,
            machineID: request.machineID,
            directory: request.directory
        )

        let response = try await service.spawnSession(
                MachineSessionSpawnServiceRequest(
                    serverURL: normalizedInputs.serverURL,
                    token: normalizedInputs.token,
                    machineID: normalizedInputs.machineID,
                    wrappedMachineDataEncryptionKey: request.wrappedMachineDataEncryptionKey,
                    directory: normalizedInputs.directory,
                agent: request.agent,
                codexResumeThreadID: normalizedOptional(request.codexResumeThreadID),
                claudeResumeSessionID: normalizedOptional(request.claudeResumeSessionID),
                approvedNewDirectoryCreation: request.approvedNewDirectoryCreation,
                sessionToken: normalizedOptional(request.sessionToken),
                environmentVariables: request.environmentVariables,
                model: normalizedOptional(request.model),
                reasoningEffort: request.reasoningEffort
            )
        )
        if response.success {
            return response
        }
        if response.requiresUserApproval == true {
            throw NewSessionError.requiresUserApproval(directory: response.directory)
        }
        let normalizedError = response.error?.trimmingCharacters(in: .whitespacesAndNewlines)
        throw NewSessionError.failed(
            message: (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "Failed to spawn session"
        )
    }
}

public actor NewSessionModelsLoadUseCase: NewSessionModelsLoadingAction {
    private let service: any MachineModelsListing

    public init(service: any MachineModelsListing) {
        self.service = service
    }

    public func loadModels(
        serverURLString: String,
        token: String,
        machineID: String,
        agent: APISessionSpawnAgent
    ) async throws -> APIMachineAgentCapabilities {
        let normalizedInputs = try normalizeInputs(
            serverURLString: serverURLString,
            token: token,
            machineID: machineID,
            directory: nil
        )
        return try await service.fetchAgentCapabilities(
            serverURL: normalizedInputs.serverURL,
            token: normalizedInputs.token,
            machineID: normalizedInputs.machineID,
            agent: agent
        )
    }
}

public actor NewSessionCodexThreadsLoadUseCase: NewSessionCodexThreadsLoadingAction {
    private let service: any MachineCodexThreadsFetching

    public init(service: any MachineCodexThreadsFetching) {
        self.service = service
    }

    public func loadCodexThreads(
        serverURLString: String,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APICodexThreadsPage {
        let normalizedInputs = try normalizeInputs(
            serverURLString: serverURLString,
            token: token,
            machineID: machineID,
            directory: nil
        )

        return try await service.fetchCodexThreadsPage(
            serverURL: normalizedInputs.serverURL,
            token: normalizedInputs.token,
            machineID: normalizedInputs.machineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            limit: limit,
            cwd: normalizedOptional(cwd),
            cursor: normalizedOptional(cursor)
        )
    }
}

public actor NewSessionClaudeSessionsLoadUseCase: NewSessionClaudeSessionsLoadingAction {
    private let service: any MachineClaudeSessionsFetching

    public init(service: any MachineClaudeSessionsFetching) {
        self.service = service
    }

    public func loadClaudeSessions(
        serverURLString: String,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APIClaudeSessionsPage {
        let normalizedInputs = try normalizeInputs(
            serverURLString: serverURLString,
            token: token,
            machineID: machineID,
            directory: nil
        )

        return try await service.fetchClaudeSessionsPage(
            serverURL: normalizedInputs.serverURL,
            token: normalizedInputs.token,
            machineID: normalizedInputs.machineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            limit: limit,
            cwd: normalizedOptional(cwd),
            cursor: normalizedOptional(cursor)
        )
    }
}

public actor NewSessionRecentProjectsUseCase: NewSessionRecentProjectsManaging {
    private let store: any AppSettingsStore
    private let maxProjects: Int

    public init(store: any AppSettingsStore, maxProjects: Int = 8) {
        self.store = store
        self.maxProjects = max(1, maxProjects)
    }

    public func loadRecentProjects() async -> [String] {
        let existing = await store.recentProjectPaths()
        let normalized = normalizeRecentProjects(existing, maxProjects: maxProjects)
        if normalized != existing {
            await store.setRecentProjectPaths(normalized)
        }
        return normalized
    }

    public func recordRecentProject(_ path: String) async -> [String] {
        guard let normalizedPath = normalizeRecentProjectPath(path) else {
            return await loadRecentProjects()
        }

        let existing = await loadRecentProjects()
        var updated = [normalizedPath]
        var seen = Set([recentProjectDedupKey(normalizedPath)])

        for item in existing {
            guard let normalizedItem = normalizeRecentProjectPath(item) else { continue }
            if seen.insert(recentProjectDedupKey(normalizedItem)).inserted {
                updated.append(normalizedItem)
            }
        }

        if updated.count > maxProjects {
            updated = Array(updated.prefix(maxProjects))
        }

        await store.setRecentProjectPaths(updated)
        return updated
    }
}

private func normalizeRecentProjects(_ value: [String], maxProjects: Int) -> [String] {
    var normalized: [String] = []
    var seen = Set<String>()

    for raw in value {
        guard let path = normalizeRecentProjectPath(raw) else { continue }
        let key = recentProjectDedupKey(path)
        guard seen.insert(key).inserted else { continue }
        normalized.append(path)
        if normalized.count >= maxProjects {
            break
        }
    }

    return normalized
}

private func recentProjectDedupKey(_ path: String) -> String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed == "~" {
        return "~"
    }
    if trimmed.hasPrefix("~/") {
        return "~/" + String(trimmed.dropFirst(2))
    }
    return trimmed
}

private func normalizeRecentProjectPath(_ raw: String) -> String? {
    var path = raw
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\\", with: "/")
    guard !path.isEmpty else {
        return nil
    }

    while path.contains("//") {
        path = path.replacingOccurrences(of: "//", with: "/")
    }

    if path == "~/" {
        path = "~"
    } else if path.hasPrefix("~/") {
        let suffix = path.dropFirst(2)
        path = suffix.isEmpty ? "~" : "~/" + suffix
    }

    if path.hasPrefix("/Users/") || path.hasPrefix("/home/") {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        if components.count >= 2 {
            let remainder = components.dropFirst(2)
            path = remainder.isEmpty ? "~" : "~/" + remainder.joined(separator: "/")
        }
    }

    if path != "/" {
        while path.hasSuffix("/") {
            path.removeLast()
            if path == "~" {
                break
            }
        }
    }

    if path == "~/" {
        path = "~"
    }

    return path.isEmpty ? nil : path
}

private func normalizedOptional(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func normalizeInputs(
    serverURLString: String,
    token: String,
    machineID: String?,
    directory: String?
) throws -> NormalizedNewSessionInputs {
    let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedToken.isEmpty else {
        throw NewSessionError.missingToken
    }

    let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
        !normalizedURL.isEmpty,
        let serverURL = URL(string: normalizedURL),
        serverURL.scheme != nil,
        serverURL.host != nil
    else {
        throw NewSessionError.invalidServerURL
    }

    let normalizedMachineID = machineID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if machineID != nil && normalizedMachineID.isEmpty {
        throw NewSessionError.missingMachineID
    }

    let normalizedDirectory = directory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if directory != nil && normalizedDirectory.isEmpty {
        throw NewSessionError.missingDirectory
    }

    return NormalizedNewSessionInputs(
        serverURL: serverURL,
        token: normalizedToken,
        machineID: normalizedMachineID,
        directory: normalizedDirectory
    )
}
