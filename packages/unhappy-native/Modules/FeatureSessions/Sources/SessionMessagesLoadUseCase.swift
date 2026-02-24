import Foundation
import CoreKit

public protocol SessionsMessagesLoading: Sendable {
    func loadMessages(serverURLString: String, token: String, sessionID: String) async throws -> [APISessionMessage]
}

public enum SessionsMessagesLoadingError: LocalizedError, Equatable {
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

public actor SessionMessagesLoadUseCase: SessionsMessagesLoading {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let sessionID: String
    }

    private let service: any SessionMessagesFetching
    private var inFlightTasks: [RequestKey: Task<[APISessionMessage], Error>] = [:]

    public init(service: any SessionMessagesFetching) {
        self.service = service
    }

    public func loadMessages(serverURLString: String, token: String, sessionID: String) async throws -> [APISessionMessage] {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw SessionsMessagesLoadingError.missingToken
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw SessionsMessagesLoadingError.invalidServerURL
        }

        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionsMessagesLoadingError.missingSessionID
        }

        let key = RequestKey(
            serverURLString: normalizedURL,
            token: normalizedToken,
            sessionID: normalizedSessionID
        )

        if let inFlightTask = inFlightTasks[key] {
            return try await inFlightTask.value
        }

        let service = self.service
        let task = Task<[APISessionMessage], Error> {
            let rows = try await service.fetchSessionMessages(
                serverURL: serverURL,
                token: normalizedToken,
                sessionID: normalizedSessionID
            )
            return rows.sorted { lhs, rhs in
                if lhs.seq == rhs.seq {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.seq < rhs.seq
            }
        }

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        return try await task.value
    }
}
