import Foundation
import CoreKit

public struct SettingsUsageSnapshot: Equatable, Sendable {
    public let totalSessions: Int
    public let activeSessions: Int
    public let inactiveSessions: Int
    public let lastUpdatedAt: TimeInterval?

    public init(
        totalSessions: Int,
        activeSessions: Int,
        inactiveSessions: Int,
        lastUpdatedAt: TimeInterval?
    ) {
        self.totalSessions = totalSessions
        self.activeSessions = activeSessions
        self.inactiveSessions = inactiveSessions
        self.lastUpdatedAt = lastUpdatedAt
    }
}

public protocol SettingsUsageLoadingAction: Sendable {
    func loadUsage(serverURLString: String, token: String) async throws -> SettingsUsageSnapshot
}

public enum SettingsUsageError: LocalizedError, Equatable {
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

public actor SettingsUsageLoadUseCase: SettingsUsageLoadingAction {
    private let service: any SessionsFetching

    public init(service: any SessionsFetching) {
        self.service = service
    }

    public func loadUsage(serverURLString: String, token: String) async throws -> SettingsUsageSnapshot {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw SettingsUsageError.missingToken
        }
        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw SettingsUsageError.invalidServerURL
        }

        let sessions = try await service.fetchSessions(
            serverURL: serverURL,
            token: normalizedToken
        )
        let activeSessions = sessions.filter(\.active).count
        let lastUpdatedAt = sessions.map(\.updatedAt).max()
        return SettingsUsageSnapshot(
            totalSessions: sessions.count,
            activeSessions: activeSessions,
            inactiveSessions: sessions.count - activeSessions,
            lastUpdatedAt: lastUpdatedAt
        )
    }
}
