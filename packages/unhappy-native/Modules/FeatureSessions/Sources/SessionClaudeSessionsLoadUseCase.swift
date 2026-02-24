import Foundation
import CoreKit

public protocol SessionClaudeSessionsLoading: Sendable {
    func loadClaudeSessions(
        serverURLString: String,
        token: String,
        sessionID: String,
        limit: Int,
        cwd: String?
    ) async throws -> [APIClaudeSessionSummary]
}

public enum SessionClaudeSessionsLoadingError: LocalizedError, Equatable {
    case missingToken
    case invalidServerURL
    case missingSessionID

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .invalidServerURL:
            return "Invalid server URL"
        case .missingSessionID:
            return "Session ID is required"
        }
    }
}

public actor SessionClaudeSessionsLoadUseCase: SessionClaudeSessionsLoading {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let sessionID: String
        let limit: Int
        let cwd: String?
    }

    private let service: any SessionClaudeSessionsFetching
    private var inFlightTasks: [RequestKey: Task<[APIClaudeSessionSummary], Error>] = [:]

    public init(service: any SessionClaudeSessionsFetching) {
        self.service = service
    }

    public func loadClaudeSessions(
        serverURLString: String,
        token: String,
        sessionID: String,
        limit: Int,
        cwd: String?
    ) async throws -> [APIClaudeSessionSummary] {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw SessionClaudeSessionsLoadingError.missingToken
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw SessionClaudeSessionsLoadingError.invalidServerURL
        }

        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionClaudeSessionsLoadingError.missingSessionID
        }
        let normalizedCWD: String? = {
            let trimmed = cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                return trimmed
            }
            return nil
        }()

        let boundedLimit = min(max(limit, 1), 100)
        let key = RequestKey(
            serverURLString: normalizedURL,
            token: normalizedToken,
            sessionID: normalizedSessionID,
            limit: boundedLimit,
            cwd: normalizedCWD
        )

        if let inFlightTask = inFlightTasks[key] {
            return try await inFlightTask.value
        }

        let service = self.service
        let task = Task<[APIClaudeSessionSummary], Error> {
            try await service.fetchClaudeSessions(
                serverURL: serverURL,
                token: normalizedToken,
                sessionID: normalizedSessionID,
                limit: boundedLimit,
                cwd: normalizedCWD
            )
        }

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        return try await task.value
    }
}
