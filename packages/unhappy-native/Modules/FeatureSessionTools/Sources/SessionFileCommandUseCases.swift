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
