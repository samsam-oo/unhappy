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
        path: String
    ) async throws -> [APIMachineDirectoryEntry]
}

public protocol NewSessionSpawningAction: Sendable {
    func spawnSession(
        serverURLString: String,
        token: String,
        machineID: String,
        directory: String,
        agent: APISessionSpawnAgent,
        approvedNewDirectoryCreation: Bool,
        codexResumeThreadID: String?,
        claudeResumeSessionID: String?,
        sessionToken: String?,
        environmentVariables: [String: String]
    ) async throws -> APISessionSpawnResult
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

public actor NewSessionMachinesLoadUseCase: NewSessionMachinesLoadingAction {
    private let service: any MachinesFetching

    public init(service: any MachinesFetching) {
        self.service = service
    }

    public func loadMachines(serverURLString: String, token: String) async throws -> [APIMachine] {
        let (serverURL, normalizedToken, _, _) = try normalizeInputs(
            serverURLString: serverURLString,
            token: token,
            machineID: nil,
            directory: nil
        )
        let rows = try await service.fetchMachines(serverURL: serverURL, token: normalizedToken)
        return rows.sorted { lhs, rhs in
            if lhs.active != rhs.active {
                return lhs.active && !rhs.active
            }
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
        path: String
    ) async throws -> [APIMachineDirectoryEntry] {
        let (serverURL, normalizedToken, normalizedMachineID, normalizedPath) = try normalizeInputs(
            serverURLString: serverURLString,
            token: token,
            machineID: machineID,
            directory: path
        )
        let result = try await service.listDirectory(
            serverURL: serverURL,
            token: normalizedToken,
            machineID: normalizedMachineID,
            path: normalizedPath
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

    public func spawnSession(
        serverURLString: String,
        token: String,
        machineID: String,
        directory: String,
        agent: APISessionSpawnAgent,
        approvedNewDirectoryCreation: Bool,
        codexResumeThreadID: String?,
        claudeResumeSessionID: String?,
        sessionToken: String?,
        environmentVariables: [String: String]
    ) async throws -> APISessionSpawnResult {
        let (serverURL, normalizedToken, normalizedMachineID, normalizedDirectory) = try normalizeInputs(
            serverURLString: serverURLString,
            token: token,
            machineID: machineID,
            directory: directory
        )

        let response = try await service.spawnSession(
            serverURL: serverURL,
            token: normalizedToken,
            machineID: normalizedMachineID,
            directory: normalizedDirectory,
            agent: agent,
            codexResumeThreadID: normalizedOptional(codexResumeThreadID),
            claudeResumeSessionID: normalizedOptional(claudeResumeSessionID),
            approvedNewDirectoryCreation: approvedNewDirectoryCreation,
            sessionToken: normalizedOptional(sessionToken),
            environmentVariables: environmentVariables
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
) throws -> (URL, String, String, String) {
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

    return (serverURL, normalizedToken, normalizedMachineID, normalizedDirectory)
}
