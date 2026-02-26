import Foundation
import CoreKit

public protocol SessionDirectoryListAction: Sendable {
    func listDirectory(
        serverURLString: String,
        token: String,
        sessionID: String,
        path: String
    ) async throws -> [APISessionDirectoryEntry]
}

public protocol SessionFileWriteAction: Sendable {
    func writeFile(
        serverURLString: String,
        token: String,
        sessionID: String,
        path: String,
        content: String,
        expectedHash: String?
    ) async throws -> APISessionWriteFileResult
}

public protocol SessionFileDiffPreviewAction: Sendable {
    func loadFileDiff(
        serverURLString: String,
        token: String,
        sessionID: String,
        path: String,
        workingDirectory: String?,
        timeout: Int?
    ) async throws -> APISessionBashResult
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

    public func listDirectory(
        serverURLString: String,
        token: String,
        sessionID: String,
        path: String
    ) async throws -> [APISessionDirectoryEntry] {
        let (serverURL, normalizedToken, normalizedSessionID, normalizedPath) = try normalizeInputs(
            serverURLString: serverURLString,
            token: token,
            sessionID: sessionID,
            path: path
        )
        let key = RequestKey(
            serverURLString: serverURL.absoluteString,
            token: normalizedToken,
            sessionID: normalizedSessionID,
            path: normalizedPath
        )
        if let inFlightTask = inFlightTasks[key] {
            return try await inFlightTask.value
        }

        let service = self.service
        let task = Task<[APISessionDirectoryEntry], Error> {
            let result = try await service.listDirectory(
                serverURL: serverURL,
                token: normalizedToken,
                sessionID: normalizedSessionID,
                path: normalizedPath
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

    public func writeFile(
        serverURLString: String,
        token: String,
        sessionID: String,
        path: String,
        content: String,
        expectedHash: String?
    ) async throws -> APISessionWriteFileResult {
        let (serverURL, normalizedToken, normalizedSessionID, normalizedPath) = try normalizeInputs(
            serverURLString: serverURLString,
            token: token,
            sessionID: sessionID,
            path: path
        )
        guard !content.isEmpty else {
            throw SessionFileCommandError.missingContent
        }
        let encoded = Data(content.utf8).base64EncodedString()
        let normalizedExpectedHash = expectedHash?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = RequestKey(
            serverURLString: serverURL.absoluteString,
            token: normalizedToken,
            sessionID: normalizedSessionID,
            path: normalizedPath,
            contentHash: encoded,
            expectedHash: normalizedExpectedHash
        )
        if let inFlightTask = inFlightTasks[key] {
            return try await inFlightTask.value
        }

        let service = self.service
        let task = Task<APISessionWriteFileResult, Error> {
            let result = try await service.writeFile(
                serverURL: serverURL,
                token: normalizedToken,
                sessionID: normalizedSessionID,
                path: normalizedPath,
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

    public func loadFileDiff(
        serverURLString: String,
        token: String,
        sessionID: String,
        path: String,
        workingDirectory: String?,
        timeout: Int? = 30_000
    ) async throws -> APISessionBashResult {
        let (_, normalizedToken, normalizedSessionID, normalizedPath) = try normalizeInputs(
            serverURLString: serverURLString,
            token: token,
            sessionID: sessionID,
            path: path
        )
        let normalizedWorkingDirectory = normalizedOptional(workingDirectory)
        let key = RequestKey(
            serverURLString: serverURLString.trimmingCharacters(in: .whitespacesAndNewlines),
            token: normalizedToken,
            sessionID: normalizedSessionID,
            path: normalizedPath,
            workingDirectory: normalizedWorkingDirectory,
            timeout: timeout
        )
        if let inFlightTask = inFlightTasks[key] {
            return try await inFlightTask.value
        }

        let basher = self.basher
        let task = Task<APISessionBashResult, Error> {
            let command = SessionFileDiffCommandBuilder.diffCommand(
                filePath: normalizedPath,
                workingDirectory: normalizedWorkingDirectory
            )
            return try await basher.runBash(
                serverURLString: serverURLString,
                token: normalizedToken,
                sessionID: normalizedSessionID,
                command: command,
                cwd: nil,
                timeout: timeout
            )
        }

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        return try await task.value
    }
}

private func normalizeInputs(
    serverURLString: String,
    token: String,
    sessionID: String,
    path: String
) throws -> (URL, String, String, String) {
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

    return (serverURL, normalizedToken, normalizedSessionID, normalizedPath)
}

private func normalizedOptional(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
