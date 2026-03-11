import Foundation
import CoreKit

public struct SessionsPageResult: Equatable, Sendable {
    public let sessions: [APISession]
    public let nextCursor: String?
    public let hasNext: Bool

    public init(sessions: [APISession], nextCursor: String?, hasNext: Bool) {
        self.sessions = sessions
        self.nextCursor = nextCursor
        self.hasNext = hasNext
    }
}

public protocol SessionsPageLoading: Sendable {
    func loadPage(
        serverURLString: String,
        token: String,
        cursor: String?,
        limit: Int
    ) async throws -> SessionsPageResult
}

public actor SessionsPageLoadUseCase: SessionsPageLoading {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let cursor: String?
        let limit: Int
    }

    private let service: any SessionsPagingFetching
    private var inFlightTasks: [RequestKey: Task<SessionsPageResult, Error>] = [:]

    public init(service: any SessionsPagingFetching) {
        self.service = service
    }

    public func loadPage(
        serverURLString: String,
        token: String,
        cursor: String? = nil,
        limit: Int = 50
    ) async throws -> SessionsPageResult {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw SessionsLoadingError.missingToken
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw SessionsLoadingError.invalidServerURL
        }

        let boundedLimit = min(max(limit, 1), 200)
        let normalizedCursor = cursor?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = RequestKey(
            serverURLString: normalizedURL,
            token: normalizedToken,
            cursor: normalizedCursor?.isEmpty == true ? nil : normalizedCursor,
            limit: boundedLimit
        )

        if let inFlightTask = inFlightTasks[key] {
            return try await inFlightTask.value
        }

        let service = self.service
        let task = Task<SessionsPageResult, Error> {
            let page = try await service.fetchSessionsPage(
                serverURL: serverURL,
                token: normalizedToken,
                cursor: key.cursor,
                limit: boundedLimit
            )

            return SessionsPageResult(
                sessions: page.sessions
                    .filter { $0.archived != true }
                    .sorted { $0.updatedAt > $1.updatedAt },
                nextCursor: page.nextCursor,
                hasNext: page.hasNext
            )
        }

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        return try await task.value
    }
}
