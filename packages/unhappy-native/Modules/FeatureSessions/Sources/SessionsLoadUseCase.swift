import Foundation
import CoreKit

public protocol SessionsLoading: Sendable {
    func loadSessions(serverURLString: String, token: String) async throws -> [APISession]
}

public enum SessionsLoadingError: LocalizedError, Equatable {
    case missingToken
    case invalidServerURL

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .invalidServerURL:
            return "Invalid server URL"
        }
    }
}

public actor SessionsLoadUseCase: SessionsLoading {
    private let service: any SessionsFetching
    private var inFlightTask: Task<[APISession], Error>?

    public init(service: any SessionsFetching) {
        self.service = service
    }

    public func loadSessions(serverURLString: String, token: String) async throws -> [APISession] {
        if let inFlightTask {
            return try await inFlightTask.value
        }

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

        let service = self.service
        let task = Task<[APISession], Error> {
            let rows = try await service.fetchSessions(serverURL: serverURL, token: normalizedToken)
            return rows
                .filter { $0.archived != true }
                .sorted { $0.updatedAt > $1.updatedAt }
        }

        inFlightTask = task
        defer { inFlightTask = nil }
        return try await task.value
    }
}
