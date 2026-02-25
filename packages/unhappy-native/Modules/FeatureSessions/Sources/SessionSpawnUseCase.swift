import Foundation
import CoreKit

public protocol SessionSpawningAction: Sendable {
    func spawnSession(
        serverURLString: String,
        token: String,
        sessionID: String,
        directory: String,
        agent: APISessionSpawnAgent?,
        codexResumeThreadID: String?,
        claudeResumeSessionID: String?,
        approvedNewDirectoryCreation: Bool?
    ) async throws -> APISessionSpawnResult
}

public enum SessionSpawnError: LocalizedError, Equatable {
    case missingToken
    case invalidServerURL
    case missingSessionID
    case missingDirectory
    case requiresUserApproval(directory: String?)
    case failed(message: String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .invalidServerURL:
            return "Invalid server URL"
        case .missingSessionID:
            return "Session ID is required"
        case .missingDirectory:
            return "Directory is required"
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

public actor SessionSpawnUseCase: SessionSpawningAction {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let sessionID: String
        let directory: String
        let agent: APISessionSpawnAgent?
        let codexResumeThreadID: String?
        let claudeResumeSessionID: String?
        let approvedNewDirectoryCreation: Bool?
    }

    private let service: any SessionSpawning
    private var inFlightTasks: [RequestKey: Task<APISessionSpawnResult, Error>] = [:]

    public init(service: any SessionSpawning) {
        self.service = service
    }

    public func spawnSession(
        serverURLString: String,
        token: String,
        sessionID: String,
        directory: String,
        agent: APISessionSpawnAgent?,
        codexResumeThreadID: String?,
        claudeResumeSessionID: String?,
        approvedNewDirectoryCreation: Bool?
    ) async throws -> APISessionSpawnResult {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw SessionSpawnError.missingToken
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw SessionSpawnError.invalidServerURL
        }

        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionSpawnError.missingSessionID
        }

        let normalizedDirectory = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDirectory.isEmpty else {
            throw SessionSpawnError.missingDirectory
        }

        let normalizedCodexResumeThreadID = codexResumeThreadID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedClaudeResumeSessionID = claudeResumeSessionID?.trimmingCharacters(in: .whitespacesAndNewlines)

        let key = RequestKey(
            serverURLString: normalizedURL,
            token: normalizedToken,
            sessionID: normalizedSessionID,
            directory: normalizedDirectory,
            agent: agent,
            codexResumeThreadID: normalizedCodexResumeThreadID?.isEmpty == true ? nil : normalizedCodexResumeThreadID,
            claudeResumeSessionID: normalizedClaudeResumeSessionID?.isEmpty == true ? nil : normalizedClaudeResumeSessionID,
            approvedNewDirectoryCreation: approvedNewDirectoryCreation
        )

        if let inFlightTask = inFlightTasks[key] {
            return try await inFlightTask.value
        }

        let service = self.service
        let task = Task<APISessionSpawnResult, Error> {
            let response = try await service.spawnSession(
                serverURL: serverURL,
                token: normalizedToken,
                sessionID: normalizedSessionID,
                directory: normalizedDirectory,
                agent: agent,
                codexResumeThreadID: key.codexResumeThreadID,
                claudeResumeSessionID: key.claudeResumeSessionID,
                approvedNewDirectoryCreation: approvedNewDirectoryCreation
            )

            if response.success {
                return response
            }

            if response.requiresUserApproval == true {
                throw SessionSpawnError.requiresUserApproval(directory: response.directory)
            }

            let normalizedError = response.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SessionSpawnError.failed(
                message: (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "Failed to spawn session"
            )
        }

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        return try await task.value
    }
}
