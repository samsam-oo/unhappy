import Foundation
import CoreKit

public enum InboxUserRelationshipStatus: String, Equatable, Sendable {
    case none
    case requested
    case pending
    case friend
    case rejected
}

public struct InboxUserProfile: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let username: String
    public let bio: String?
    public let status: InboxUserRelationshipStatus

    public init(
        id: String,
        displayName: String,
        username: String,
        bio: String?,
        status: InboxUserRelationshipStatus
    ) {
        self.id = id
        self.displayName = displayName
        self.username = username
        self.bio = bio
        self.status = status
    }
}

public protocol InboxUserProfileLoadingAction: Sendable {
    func loadUserProfile(
        serverURLString: String,
        token: String,
        userID: String
    ) async throws -> InboxUserProfile?
}

public protocol InboxUserSearchingAction: Sendable {
    func searchUsers(
        serverURLString: String,
        token: String,
        query: String
    ) async throws -> [InboxUserProfile]
}

public enum InboxUserLookupError: LocalizedError, Equatable {
    case missingToken
    case invalidServerURL
    case missingUserID
    case missingQuery

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .invalidServerURL:
            return "Invalid server URL"
        case .missingUserID:
            return "User ID is required"
        case .missingQuery:
            return "Query is required"
        }
    }
}

public actor InboxUserProfileLoadUseCase: InboxUserProfileLoadingAction {
    private let service: any UserProfileFetching

    public init(service: any UserProfileFetching) {
        self.service = service
    }

    public func loadUserProfile(
        serverURLString: String,
        token: String,
        userID: String
    ) async throws -> InboxUserProfile? {
        let normalized = try normalizeInputs(
            serverURLString: serverURLString,
            token: token,
            userID: userID
        )
        let profile = try await service.fetchUserProfile(
            serverURL: normalized.serverURL,
            token: normalized.token,
            userID: normalized.userID
        )
        return profile.map(mapUserProfile(_:))
    }
}

public actor InboxUserSearchUseCase: InboxUserSearchingAction {
    private let service: any UserSearchFetching
    private var inFlightTasks: [SearchTaskKey: Task<[InboxUserProfile], Error>] = [:]

    public init(service: any UserSearchFetching) {
        self.service = service
    }

    public func searchUsers(
        serverURLString: String,
        token: String,
        query: String
    ) async throws -> [InboxUserProfile] {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw InboxUserLookupError.missingToken
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw InboxUserLookupError.invalidServerURL
        }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            throw InboxUserLookupError.missingQuery
        }

        let key = SearchTaskKey(
            serverURLString: normalizedURL,
            token: normalizedToken,
            query: normalizedQuery
        )
        if let task = inFlightTasks[key] {
            return try await task.value
        }

        let service = self.service
        let task = Task<[InboxUserProfile], Error> {
            let rows = try await service.searchUsers(
                serverURL: serverURL,
                token: normalizedToken,
                query: normalizedQuery
            )
            return rows.map(mapUserProfile(_:))
        }
        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        return try await task.value
    }
}

public struct InboxNoopUserProfileLoader: InboxUserProfileLoadingAction {
    public init() {}

    public func loadUserProfile(
        serverURLString: String,
        token: String,
        userID: String
    ) async throws -> InboxUserProfile? {
        nil
    }
}

public struct InboxNoopUserSearcher: InboxUserSearchingAction {
    public init() {}

    public func searchUsers(
        serverURLString: String,
        token: String,
        query: String
    ) async throws -> [InboxUserProfile] {
        []
    }
}

private struct SearchTaskKey: Hashable, Sendable {
    let serverURLString: String
    let token: String
    let query: String
}

private func normalizeInputs(
    serverURLString: String,
    token: String,
    userID: String
) throws -> (serverURL: URL, token: String, userID: String) {
    let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedToken.isEmpty else {
        throw InboxUserLookupError.missingToken
    }

    let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
        !normalizedURL.isEmpty,
        let serverURL = URL(string: normalizedURL),
        serverURL.scheme != nil,
        serverURL.host != nil
    else {
        throw InboxUserLookupError.invalidServerURL
    }

    let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedUserID.isEmpty else {
        throw InboxUserLookupError.missingUserID
    }

    return (serverURL, normalizedToken, normalizedUserID)
}

private func mapUserProfile(_ profile: APIUserProfile) -> InboxUserProfile {
    InboxUserProfile(
        id: profile.id,
        displayName: profile.displayName,
        username: profile.username,
        bio: profile.bio,
        status: InboxUserRelationshipStatus(rawValue: profile.status.rawValue) ?? .none
    )
}
