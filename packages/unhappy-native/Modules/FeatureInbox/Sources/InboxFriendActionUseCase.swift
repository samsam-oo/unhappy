import Foundation
import CoreKit

public protocol InboxFriendActionPerforming: Sendable {
    func acceptFriendRequest(
        serverURLString: String,
        token: String,
        userID: String
    ) async throws
    func rejectFriendRequest(
        serverURLString: String,
        token: String,
        userID: String
    ) async throws
    func cancelFriendRequest(
        serverURLString: String,
        token: String,
        userID: String
    ) async throws
    func removeFriend(
        serverURLString: String,
        token: String,
        userID: String
    ) async throws
}

public enum InboxFriendActionError: LocalizedError, Equatable {
    case missingToken
    case invalidServerURL
    case missingUserID

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .invalidServerURL:
            return "Invalid server URL"
        case .missingUserID:
            return "User ID is required"
        }
    }
}

public actor InboxFriendActionUseCase: InboxFriendActionPerforming {
    private let adder: any FriendAdding
    private let remover: any FriendRemoving

    public init(
        adder: any FriendAdding,
        remover: any FriendRemoving
    ) {
        self.adder = adder
        self.remover = remover
    }

    public func acceptFriendRequest(
        serverURLString: String,
        token: String,
        userID: String
    ) async throws {
        let normalized = try normalizeInputs(
            serverURLString: serverURLString,
            token: token,
            userID: userID
        )
        _ = try await adder.addFriend(
            serverURL: normalized.serverURL,
            token: normalized.token,
            userID: normalized.userID
        )
    }

    public func rejectFriendRequest(
        serverURLString: String,
        token: String,
        userID: String
    ) async throws {
        let normalized = try normalizeInputs(
            serverURLString: serverURLString,
            token: token,
            userID: userID
        )
        _ = try await remover.removeFriend(
            serverURL: normalized.serverURL,
            token: normalized.token,
            userID: normalized.userID
        )
    }

    public func cancelFriendRequest(
        serverURLString: String,
        token: String,
        userID: String
    ) async throws {
        let normalized = try normalizeInputs(
            serverURLString: serverURLString,
            token: token,
            userID: userID
        )
        _ = try await remover.removeFriend(
            serverURL: normalized.serverURL,
            token: normalized.token,
            userID: normalized.userID
        )
    }

    public func removeFriend(
        serverURLString: String,
        token: String,
        userID: String
    ) async throws {
        let normalized = try normalizeInputs(
            serverURLString: serverURLString,
            token: token,
            userID: userID
        )
        _ = try await remover.removeFriend(
            serverURL: normalized.serverURL,
            token: normalized.token,
            userID: normalized.userID
        )
    }
}

public struct InboxNoopFriendActionUseCase: InboxFriendActionPerforming {
    public init() {}

    public func acceptFriendRequest(
        serverURLString: String,
        token: String,
        userID: String
    ) async throws {}

    public func rejectFriendRequest(
        serverURLString: String,
        token: String,
        userID: String
    ) async throws {}

    public func cancelFriendRequest(
        serverURLString: String,
        token: String,
        userID: String
    ) async throws {}

    public func removeFriend(
        serverURLString: String,
        token: String,
        userID: String
    ) async throws {}
}

private func normalizeInputs(
    serverURLString: String,
    token: String,
    userID: String
) throws -> (serverURL: URL, token: String, userID: String) {
    let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedToken.isEmpty else {
        throw InboxFriendActionError.missingToken
    }

    let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
        !normalizedURL.isEmpty,
        let serverURL = URL(string: normalizedURL),
        serverURL.scheme != nil,
        serverURL.host != nil
    else {
        throw InboxFriendActionError.invalidServerURL
    }

    let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedUserID.isEmpty else {
        throw InboxFriendActionError.missingUserID
    }

    return (serverURL, normalizedToken, normalizedUserID)
}
