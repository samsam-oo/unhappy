import Foundation
import CoreKit

public protocol SessionDirectoryListAction: Sendable {
    func listDirectory(_ request: SessionDirectoryListRequest) async throws -> [APISessionDirectoryEntry]
}

public protocol SessionFileWriteAction: Sendable {
    func writeFile(_ request: SessionFileWriteRequest) async throws -> APISessionWriteFileResult
}

public protocol SessionFileDiffPreviewAction: Sendable {
    func loadFileDiff(_ request: SessionFileDiffPreviewRequest) async throws -> APISessionBashResult
}

public struct SessionDirectoryListRequest: Sendable, Equatable {
    public let serverURLString: String
    public let token: String
    public let sessionID: String
    public let path: String
}

public struct SessionFileWriteRequest: Sendable, Equatable {
    public let serverURLString: String
    public let token: String
    public let sessionID: String
    public let path: String
    public let content: String
    public let expectedHash: String?
}

public struct SessionFileDiffPreviewRequest: Sendable, Equatable {
    public let serverURLString: String
    public let token: String
    public let sessionID: String
    public let path: String
    public let workingDirectory: String?
    public let timeout: Int?
}

public enum SessionFileCommandError: LocalizedError, Equatable {
    case missingToken
    case invalidServerURL
    case missingSessionID
    case missingPath
    case missingContent
    case failed(message: String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .invalidServerURL:
            return "Invalid server URL"
        case .missingSessionID:
            return "Session ID is required"
        case .missingPath:
            return "Path is required"
        case .missingContent:
            return "File content is required"
        case .failed(let message):
            return message
        }
    }
}

public actor SessionDirectoryListUseCase: SessionDirectoryListAction {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let sessionID: String
        let path: String
    }

    private let service: any SessionDirectoryListing
    private var inFlightTasks: [RequestKey: Task<[APISessionDirectoryEntry], Error>] = [:]

    public init(service: any SessionDirectoryListing) {
        self.service = service
    }

    public func listDirectory(_ request: SessionDirectoryListRequest) async throws -> [APISessionDirectoryEntry] {
        let normalized = try normalizeInputs(
            serverURLString: request.serverURLString,
            token: request.token,
            sessionID: request.sessionID,
            path: request.path
        )
        let key = RequestKey(
            serverURLString: normalized.serverURL.absoluteString,
            token: normalized.token,
            sessionID: normalized.sessionID,
            path: normalized.path
        )
        if let inFlightTask = inFlightTasks[key] {
            return try await inFlightTask.value
        }

        let service = self.service
        let task = Task<[APISessionDirectoryEntry], Error> {
            let result = try await service.listDirectory(
                serverURL: normalized.serverURL,
                token: normalized.token,
                sessionID: normalized.sessionID,
                path: normalized.path
            )

            guard result.success else {
                let normalizedError = result.error?.trimmingCharacters(in: .whitespacesAndNewlines)
                throw SessionFileCommandError.failed(
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

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        return try await task.value
    }
}

public actor SessionFileWriteUseCase: SessionFileWriteAction {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let sessionID: String
        let path: String
        let contentHash: String
        let expectedHash: String?
    }

    private let service: any SessionFileWriting
    private var inFlightTasks: [RequestKey: Task<APISessionWriteFileResult, Error>] = [:]

    public init(service: any SessionFileWriting) {
        self.service = service
    }

    public func writeFile(_ request: SessionFileWriteRequest) async throws -> APISessionWriteFileResult {
        let normalized = try normalizeInputs(
            serverURLString: request.serverURLString,
            token: request.token,
            sessionID: request.sessionID,
            path: request.path
        )
        guard !request.content.isEmpty else {
            throw SessionFileCommandError.missingContent
        }
        let encoded = Data(request.content.utf8).base64EncodedString()
        let normalizedExpectedHash = request.expectedHash?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = RequestKey(
            serverURLString: normalized.serverURL.absoluteString,
            token: normalized.token,
            sessionID: normalized.sessionID,
            path: normalized.path,
            contentHash: encoded,
            expectedHash: normalizedExpectedHash
        )
        if let inFlightTask = inFlightTasks[key] {
            return try await inFlightTask.value
        }

        let service = self.service
        let task = Task<APISessionWriteFileResult, Error> {
            let result = try await service.writeFile(
                serverURL: normalized.serverURL,
                token: normalized.token,
                sessionID: normalized.sessionID,
                path: normalized.path,
                content: encoded,
                expectedHash: normalizedExpectedHash
            )
            if result.success {
                return result
            }
            let normalizedError = result.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SessionFileCommandError.failed(
                message: (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "Failed to write file"
            )
        }

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        return try await task.value
    }
}

public actor SessionFileDiffPreviewUseCase: SessionFileDiffPreviewAction {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let sessionID: String
        let path: String
        let workingDirectory: String?
        let timeout: Int?
    }

    private let basher: any SessionBashRunAction
    private var inFlightTasks: [RequestKey: Task<APISessionBashResult, Error>] = [:]

    public init(basher: any SessionBashRunAction) {
        self.basher = basher
    }

    public func loadFileDiff(_ request: SessionFileDiffPreviewRequest) async throws -> APISessionBashResult {
        let normalized = try normalizeInputs(
            serverURLString: request.serverURLString,
            token: request.token,
            sessionID: request.sessionID,
            path: request.path
        )
        let normalizedWorkingDirectory = normalizedOptional(request.workingDirectory)
        let key = RequestKey(
            serverURLString: request.serverURLString.trimmingCharacters(in: .whitespacesAndNewlines),
            token: normalized.token,
            sessionID: normalized.sessionID,
            path: normalized.path,
            workingDirectory: normalizedWorkingDirectory,
            timeout: request.timeout
        )
        if let inFlightTask = inFlightTasks[key] {
            return try await inFlightTask.value
        }

        let basher = self.basher
        let task = Task<APISessionBashResult, Error> {
            let command = SessionFileDiffCommandBuilder.diffCommand(
                filePath: normalized.path,
                workingDirectory: normalizedWorkingDirectory
            )
            return try await basher.runBash(
                SessionBashCommandRequest(
                    serverURLString: request.serverURLString,
                    token: normalized.token,
                    sessionID: normalized.sessionID,
                    command: command,
                    cwd: nil,
                    timeout: request.timeout
                )
            )
        }

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        return try await task.value
    }
}

private struct SessionFileNormalizedInput {
    let serverURL: URL
    let token: String
    let sessionID: String
    let path: String
}

private func normalizeInputs(
    serverURLString: String,
    token: String,
    sessionID: String,
    path: String
) throws -> SessionFileNormalizedInput {
    let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedToken.isEmpty else {
        throw SessionFileCommandError.missingToken
    }

    let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
        !normalizedURL.isEmpty,
        let serverURL = URL(string: normalizedURL),
        serverURL.scheme != nil,
        serverURL.host != nil
    else {
        throw SessionFileCommandError.invalidServerURL
    }

    let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedSessionID.isEmpty else {
        throw SessionFileCommandError.missingSessionID
    }

    let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedPath.isEmpty else {
        throw SessionFileCommandError.missingPath
    }

    return SessionFileNormalizedInput(
        serverURL: serverURL,
        token: normalizedToken,
        sessionID: normalizedSessionID,
        path: normalizedPath
    )
}

private func normalizedOptional(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
