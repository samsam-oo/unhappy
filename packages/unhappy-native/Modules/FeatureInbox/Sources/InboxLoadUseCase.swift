import Foundation
import CoreKit

public struct InboxItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let timestamp: Date

    public init(id: String, title: String, subtitle: String, timestamp: Date) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.timestamp = timestamp
    }
}

public struct InboxFriend: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let subtitle: String

    public init(id: String, displayName: String, subtitle: String) {
        self.id = id
        self.displayName = displayName
        self.subtitle = subtitle
    }
}

public struct InboxSnapshot: Equatable, Sendable {
    public let feedItems: [InboxItem]
    public let friendRequests: [InboxFriend]
    public let requestedFriends: [InboxFriend]
    public let friends: [InboxFriend]

    public init(
        feedItems: [InboxItem],
        friendRequests: [InboxFriend],
        requestedFriends: [InboxFriend],
        friends: [InboxFriend]
    ) {
        self.feedItems = feedItems
        self.friendRequests = friendRequests
        self.requestedFriends = requestedFriends
        self.friends = friends
    }

    public var isEmpty: Bool {
        feedItems.isEmpty
        && friendRequests.isEmpty
        && requestedFriends.isEmpty
        && friends.isEmpty
    }
}

public protocol InboxLoadingAction: Sendable {
    func loadInboxSnapshot(serverURLString: String, token: String) async throws -> InboxSnapshot
}

public enum InboxLoadingError: LocalizedError, Equatable {
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

public actor InboxLoadUseCase: InboxLoadingAction {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let limit: Int
    }

    private let feedService: any FeedFetching
    private let friendsService: any FriendsFetching
    private let limit: Int
    private var inFlightTasks: [RequestKey: Task<InboxSnapshot, Error>] = [:]

    public init(
        service: any FeedFetching,
        friendsService: any FriendsFetching,
        limit: Int = 50
    ) {
        self.feedService = service
        self.friendsService = friendsService
        self.limit = limit
    }

    public func loadInboxSnapshot(serverURLString: String, token: String) async throws -> InboxSnapshot {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw InboxLoadingError.missingToken
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw InboxLoadingError.invalidServerURL
        }

        let boundedLimit = min(max(limit, 1), 200)
        let requestKey = RequestKey(
            serverURLString: normalizedURL,
            token: normalizedToken,
            limit: boundedLimit
        )
        if let inFlightTask = inFlightTasks[requestKey] {
            return try await inFlightTask.value
        }

        let feedService = self.feedService
        let friendsService = self.friendsService
        let task = Task<InboxSnapshot, Error> {
            async let feedPage = feedService.fetchFeed(
                serverURL: serverURL,
                token: normalizedToken,
                before: nil,
                after: nil,
                limit: boundedLimit
            )
            async let profiles = friendsService.fetchFriends(
                serverURL: serverURL,
                token: normalizedToken
            )

            let mappedFeedItems = try await feedPage.items.map(Self.makeInboxItem(from:))
            let friendProfiles = try await profiles
            return Self.makeSnapshot(
                feedItems: mappedFeedItems,
                friendProfiles: friendProfiles
            )
        }

        inFlightTasks[requestKey] = task
        defer { inFlightTasks[requestKey] = nil }
        return try await task.value
    }
}

private extension InboxLoadUseCase {
    static func makeInboxItem(from row: APIFeedItem) -> InboxItem {
        let timestamp = Date(timeIntervalSince1970: row.createdAt / 1000)

        let title: String
        let subtitle: String
        switch row.body {
        case .friendRequest(let uid):
            title = "Friend request"
            subtitle = "From \(uid)"
        case .friendAccepted(let uid):
            title = "Friend request accepted"
            subtitle = uid
        case .text(let text):
            title = text
            subtitle = "Feed update"
        }

        return InboxItem(
            id: row.id,
            title: title,
            subtitle: subtitle,
            timestamp: timestamp
        )
    }

    static func makeSnapshot(
        feedItems: [InboxItem],
        friendProfiles: [APIUserProfile]
    ) -> InboxSnapshot {
        let friendRequests = friendProfiles
            .filter { $0.status == .pending }
            .map(makeInboxFriend(from:))
            .sorted { sortByName(lhs: $0, rhs: $1) }
        let requestedFriends = friendProfiles
            .filter { $0.status == .requested }
            .map(makeInboxFriend(from:))
            .sorted { sortByName(lhs: $0, rhs: $1) }
        let acceptedFriends = friendProfiles
            .filter { $0.status == .friend }
            .map(makeInboxFriend(from:))
            .sorted { sortByName(lhs: $0, rhs: $1) }

        return InboxSnapshot(
            feedItems: feedItems,
            friendRequests: friendRequests,
            requestedFriends: requestedFriends,
            friends: acceptedFriends
        )
    }

    static func makeInboxFriend(from profile: APIUserProfile) -> InboxFriend {
        let username = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = username.isEmpty ? "user" : "@\(username)"
        return InboxFriend(
            id: profile.id,
            displayName: profile.displayName,
            subtitle: subtitle
        )
    }

    static func sortByName(lhs: InboxFriend, rhs: InboxFriend) -> Bool {
        lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
}
