import Foundation
import Testing
@testable import FeatureInbox
import CoreKit

struct InboxLoadUseCaseTests {
    @Test
    func loadInboxSnapshotThrowsMissingToken() async {
        let useCase = InboxLoadUseCase(
            service: MockFeedService(page: APIFeedPage(items: [], hasMore: false)),
            friendsService: MockFriendsService(friends: [])
        )

        await #expect(throws: InboxLoadingError.missingToken) {
            _ = try await useCase.loadInboxSnapshot(
                serverURLString: "https://api.unhappy.im",
                token: " "
            )
        }
    }

    @Test
    func loadInboxSnapshotThrowsInvalidServerURL() async {
        let useCase = InboxLoadUseCase(
            service: MockFeedService(page: APIFeedPage(items: [], hasMore: false)),
            friendsService: MockFriendsService(friends: [])
        )

        await #expect(throws: InboxLoadingError.invalidServerURL) {
            _ = try await useCase.loadInboxSnapshot(
                serverURLString: "not-a-url",
                token: "token"
            )
        }
    }

    @Test
    func loadInboxSnapshotMapsFeedAndFriends() async throws {
        let feedRows: [APIFeedItem] = [
            APIFeedItem(
                id: "f1",
                body: .friendRequest(uid: "user_a"),
                repeatKey: nil,
                cursor: "0-10",
                createdAt: 1_735_689_600_000
            ),
            APIFeedItem(
                id: "f2",
                body: .text(text: "Daemon updated"),
                repeatKey: nil,
                cursor: "0-11",
                createdAt: 1_735_689_700_000
            )
        ]
        let friendRows: [APIUserProfile] = [
            APIUserProfile(
                id: "u3",
                firstName: "Zeta",
                lastName: nil,
                avatar: nil,
                username: "zeta",
                bio: nil,
                status: .requested
            ),
            APIUserProfile(
                id: "u1",
                firstName: "Alpha",
                lastName: nil,
                avatar: nil,
                username: "alpha",
                bio: nil,
                status: .pending
            ),
            APIUserProfile(
                id: "u2",
                firstName: "",
                lastName: nil,
                avatar: nil,
                username: "friend2",
                bio: nil,
                status: .friend
            )
        ]

        let useCase = InboxLoadUseCase(
            service: MockFeedService(page: APIFeedPage(items: feedRows, hasMore: false)),
            friendsService: MockFriendsService(friends: friendRows)
        )

        let snapshot = try await useCase.loadInboxSnapshot(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(snapshot.feedItems.count == 2)
        #expect(snapshot.feedItems[0].title == "Friend request")
        #expect(snapshot.feedItems[1].title == "Daemon updated")
        #expect(snapshot.feedItems[0].timestamp == Date(timeIntervalSince1970: 1_735_689_600))
        #expect(snapshot.friendRequests.map(\.id) == ["u1"])
        #expect(snapshot.requestedFriends.map(\.id) == ["u3"])
        #expect(snapshot.friends.map(\.id) == ["u2"])
    }

    @Test
    func concurrentLoadsShareSingleInFlightRequest() async throws {
        let feedService = SlowCountingFeedService(
            page: APIFeedPage(
                items: [
                    APIFeedItem(
                        id: "f1",
                        body: .text(text: "Hello"),
                        repeatKey: nil,
                        cursor: "0-1",
                        createdAt: 1_735_689_600_000
                    )
                ],
                hasMore: false
            )
        )
        let friendsService = SlowCountingFriendsService(
            friends: [
                APIUserProfile(
                    id: "u1",
                    firstName: "User",
                    lastName: nil,
                    avatar: nil,
                    username: "user",
                    bio: nil,
                    status: .friend
                )
            ]
        )
        let useCase = InboxLoadUseCase(
            service: feedService,
            friendsService: friendsService
        )

        async let first = useCase.loadInboxSnapshot(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )
        async let second = useCase.loadInboxSnapshot(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        _ = try await first
        _ = try await second

        #expect(await feedService.fetchCount() == 1)
        #expect(await friendsService.fetchCount() == 1)
    }
}

private struct MockFeedService: FeedFetching {
    let page: APIFeedPage

    func fetchFeed(
        serverURL: URL,
        token: String,
        before: String?,
        after: String?,
        limit: Int
    ) async throws -> APIFeedPage {
        page
    }
}

private struct MockFriendsService: FriendsFetching {
    let friends: [APIUserProfile]

    func fetchFriends(serverURL: URL, token: String) async throws -> [APIUserProfile] {
        friends
    }
}

private actor SlowCountingFeedService: FeedFetching {
    private let page: APIFeedPage
    private var count: Int = 0

    init(page: APIFeedPage) {
        self.page = page
    }

    func fetchFeed(
        serverURL: URL,
        token: String,
        before: String?,
        after: String?,
        limit: Int
    ) async throws -> APIFeedPage {
        count += 1
        try await Task.sleep(nanoseconds: 80_000_000)
        return page
    }

    func fetchCount() -> Int {
        count
    }
}

private actor SlowCountingFriendsService: FriendsFetching {
    private let friends: [APIUserProfile]
    private var count: Int = 0

    init(friends: [APIUserProfile]) {
        self.friends = friends
    }

    func fetchFriends(serverURL: URL, token: String) async throws -> [APIUserProfile] {
        count += 1
        try await Task.sleep(nanoseconds: 80_000_000)
        return friends
    }

    func fetchCount() -> Int {
        count
    }
}
