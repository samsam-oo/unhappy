import Foundation
import CoreKit

public protocol MachineSpawnAction: Sendable {
    func spawnSession(
        serverURLString: String,
        token: String,
        machineID: String,
        directory: String,
        agent: APISessionSpawnAgent?,
        approvedNewDirectoryCreation: Bool
    ) async throws -> APISessionSpawnResult
}

public enum MachineSpawnError: LocalizedError, Equatable {
    case missingToken
    case invalidServerURL
    case missingMachineID
    case missingDirectory
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

public actor MachineSpawnUseCase: MachineSpawnAction {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let machineID: String
        let directory: String
        let agent: APISessionSpawnAgent?
        let approvedNewDirectoryCreation: Bool
    }

    private let service: any MachineSessionSpawning
    private var inFlightTasks: [RequestKey: Task<APISessionSpawnResult, Error>] = [:]

    public init(service: any MachineSessionSpawning) {
        self.service = service
    }

    public func spawnSession(
        serverURLString: String,
        token: String,
        machineID: String,
        directory: String,
        agent: APISessionSpawnAgent?,
        approvedNewDirectoryCreation: Bool
    ) async throws -> APISessionSpawnResult {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw MachineSpawnError.missingToken
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw MachineSpawnError.invalidServerURL
        }

        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachineSpawnError.missingMachineID
        }

        let normalizedDirectory = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDirectory.isEmpty else {
            throw MachineSpawnError.missingDirectory
        }

        let key = RequestKey(
            serverURLString: normalizedURL,
            token: normalizedToken,
            machineID: normalizedMachineID,
            directory: normalizedDirectory,
            agent: agent,
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
                machineID: normalizedMachineID,
                directory: normalizedDirectory,
                agent: agent,
                codexResumeThreadID: nil,
                claudeResumeSessionID: nil,
                approvedNewDirectoryCreation: approvedNewDirectoryCreation,
                sessionToken: nil,
                environmentVariables: nil,
                model: nil,
                reasoningEffort: nil
            )

            if response.success {
                return response
            }
            if response.requiresUserApproval == true {
                throw MachineSpawnError.requiresUserApproval(directory: response.directory)
            }

            let normalizedError = response.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MachineSpawnError.failed(
                message: (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "Failed to spawn session"
            )
        }

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        return try await task.value
    }
}
