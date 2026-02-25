import Foundation
import Testing
@testable import FeatureInbox
import CoreKit

struct InboxLoadUseCaseTests {
    @Test
    func loadInboxItemsThrowsMissingToken() async {
        let useCase = InboxLoadUseCase(service: MockFeedService(page: APIFeedPage(items: [], hasMore: false)))

        await #expect(throws: InboxLoadingError.missingToken) {
            _ = try await useCase.loadInboxItems(
                serverURLString: "https://api.unhappy.im",
                token: " "
            )
        }
    }

    @Test
    func loadInboxItemsThrowsInvalidServerURL() async {
        let useCase = InboxLoadUseCase(service: MockFeedService(page: APIFeedPage(items: [], hasMore: false)))

        await #expect(throws: InboxLoadingError.invalidServerURL) {
            _ = try await useCase.loadInboxItems(
                serverURLString: "not-a-url",
                token: "token"
            )
        }
    }

    @Test
    func loadInboxItemsMapsFeedRows() async throws {
        let rows: [APIFeedItem] = [
            APIFeedItem(
                id: "f1",
                body: .friendRequest(uid: "user_a"),
                repeatKey: nil,
                cursor: "0-10",
                createdAt: 1_735_689_600_000
            ),
            APIFeedItem(
                id: "f2",
                body: .friendAccepted(uid: "user_b"),
                repeatKey: nil,
                cursor: "0-11",
                createdAt: 1_735_689_700_000
            ),
            APIFeedItem(
                id: "f3",
                body: .text(text: "Daemon updated"),
                repeatKey: nil,
                cursor: "0-12",
                createdAt: 1_735_689_800_000
            )
        ]
        let useCase = InboxLoadUseCase(
            service: MockFeedService(page: APIFeedPage(items: rows, hasMore: false))
        )

        let loaded = try await useCase.loadInboxItems(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(loaded.count == 3)
        #expect(loaded[0].title == "Friend request")
        #expect(loaded[0].subtitle == "From user_a")
        #expect(loaded[1].title == "Friend request accepted")
        #expect(loaded[1].subtitle == "user_b")
        #expect(loaded[2].title == "Daemon updated")
        #expect(loaded[2].subtitle == "Feed update")
        #expect(loaded[0].timestamp == Date(timeIntervalSince1970: 1_735_689_600))
    }

    @Test
    func concurrentLoadsShareSingleInFlightRequest() async throws {
        let service = SlowCountingFeedService(
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
        let useCase = InboxLoadUseCase(service: service)

        async let first = useCase.loadInboxItems(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )
        async let second = useCase.loadInboxItems(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        _ = try await first
        _ = try await second

        #expect(await service.fetchCount() == 1)
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
