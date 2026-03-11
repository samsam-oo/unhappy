import Foundation
import Testing
@testable import FeatureSessions
import CoreKit
import SessionKit

struct SessionsPageLoadUseCaseTests {
    @Test
    func loadPageThrowsMissingToken() async {
        let useCase = SessionsPageLoadUseCase(service: ImmediatePagingService(page: APISessionsPage(sessions: [], nextCursor: nil, hasNext: false)))

        await #expect(throws: SessionsLoadingError.missingToken) {
            _ = try await useCase.loadPage(
                serverURLString: "https://api.unhappy.im",
                token: " ",
                cursor: nil,
                limit: 50
            )
        }
    }

    @Test
    func loadPageReturnsSortedRowsAndCursor() async throws {
        let page = APISessionsPage(
            sessions: [
                APISession(
                    id: "old",
                    active: false,
                    activeAt: 1,
                    createdAt: 1,
                    updatedAt: 10,
                    metadataVersion: 1,
                    metadata: "enc",
                    dataEncryptionKey: nil,
                    lastMessage: nil
                ),
                APISession(
                    id: "new",
                    active: false,
                    activeAt: 1,
                    createdAt: 1,
                    updatedAt: 20,
                    metadataVersion: 1,
                    metadata: "enc",
                    dataEncryptionKey: nil,
                    lastMessage: nil
                )
            ],
            nextCursor: "cursor_v1_new",
            hasNext: true
        )
        let useCase = SessionsPageLoadUseCase(service: ImmediatePagingService(page: page))

        let result = try await useCase.loadPage(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            cursor: nil,
            limit: 50
        )

        #expect(result.sessions.map(\.id) == ["new", "old"])
        #expect(result.nextCursor == "cursor_v1_new")
        #expect(result.hasNext == true)
    }

    @Test
    func loadPageFiltersArchivedRows() async throws {
        let page = APISessionsPage(
            sessions: [
                APISession(
                    id: "archived",
                    active: false,
                    activeAt: 1,
                    createdAt: 1,
                    updatedAt: 25,
                    archived: true,
                    metadataVersion: 1,
                    metadata: "enc",
                    dataEncryptionKey: nil,
                    lastMessage: nil
                ),
                APISession(
                    id: "visible",
                    active: false,
                    activeAt: 1,
                    createdAt: 1,
                    updatedAt: 20,
                    archived: false,
                    metadataVersion: 1,
                    metadata: "enc",
                    dataEncryptionKey: nil,
                    lastMessage: nil
                )
            ],
            nextCursor: "cursor_v1_visible",
            hasNext: true
        )
        let useCase = SessionsPageLoadUseCase(service: ImmediatePagingService(page: page))

        let result = try await useCase.loadPage(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            cursor: nil,
            limit: 50
        )

        #expect(result.sessions.map { $0.id } == ["visible"])
        #expect(result.nextCursor == "cursor_v1_visible")
        #expect(result.hasNext == true)
    }
}

private struct ImmediatePagingService: SessionsPagingFetching {
    let page: APISessionsPage

    func fetchSessionsPage(serverURL: URL, token: String, cursor: String?, limit: Int) async throws -> APISessionsPage {
        page
    }
}
