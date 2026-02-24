import Foundation
import Testing
@testable import FeatureSessions
import CoreKit

@MainActor
struct SessionsViewModelTests {
    @Test
    func loadSuccessPublishesSessions() async throws {
        let expected = [
            APISession(
                id: "s1",
                active: true,
                activeAt: 10,
                createdAt: 1,
                updatedAt: 11,
                metadataVersion: 2,
                metadata: "enc",
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let loader = MockSessionsLoader(result: .success(expected))
        let model = SessionsViewModel(
            loader: loader,
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: expected, nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([])),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.load(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(model.sessions.count == 1)
        #expect(model.errorMessage == nil)
        #expect(model.multiAgentInProgress == true)
    }

    @Test
    func loadWithoutTokenSetsValidationError() async throws {
        let model = SessionsViewModel(
            service: MockSessionsServiceForValidation()
        )

        await model.load(serverURLString: "https://api.unhappy.im", token: "")

        #expect(model.sessions.isEmpty)
        #expect(model.errorMessage == "API token is required")
        #expect(model.multiAgentInProgress == false)
    }

    @Test
    func loadWithInactiveSessionsMarksMultiAgentCompleted() async throws {
        let expected = [
            APISession(
                id: "s2",
                active: false,
                activeAt: 10,
                createdAt: 1,
                updatedAt: 11,
                metadataVersion: 2,
                metadata: "enc",
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let loader = MockSessionsLoader(result: .success(expected))
        let model = SessionsViewModel(
            loader: loader,
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: expected, nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([])),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.load(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(model.errorMessage == nil)
        #expect(model.multiAgentInProgress == false)
    }

    @Test
    func startPollingPublishesRowsFromPoller() async throws {
        let expected = [
            APISession(
                id: "poll",
                active: true,
                activeAt: 1,
                createdAt: 1,
                updatedAt: 3,
                metadataVersion: 1,
                metadata: "enc",
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: expected),
            messageLoader: MockSessionsMessagesLoader(result: .success([])),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.startPolling(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            interval: .seconds(60)
        )

        #expect(model.sessions == expected)
        #expect(model.errorMessage == nil)
        #expect(model.isLoading == false)
    }

    @Test
    func loadMessagesSuccessPublishesSelectedSessionMessages() async throws {
        let message = APISessionMessage(
            id: "m1",
            seq: 1,
            localId: "l1",
            content: APIEncryptedMessageContent(t: "encrypted", c: "abc"),
            createdAt: 10,
            updatedAt: 12
        )
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([message])),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.loadMessages(
            for: "session-1",
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(model.selectedSessionID == "session-1")
        #expect(model.selectedSessionMessages == [message])
        #expect(model.selectedSessionErrorMessage == nil)
    }

    @Test
    func deleteSessionRemovesSessionFromList() async throws {
        let sessions = [
            APISession(
                id: "s1",
                active: false,
                activeAt: 10,
                createdAt: 1,
                updatedAt: 11,
                metadataVersion: 2,
                metadata: "enc",
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success(sessions)),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: sessions, nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([])),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.load(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )
        await model.deleteSession(
            sessionID: "s1",
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(model.sessions.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test
    func messageCacheIsBoundedToPreventUnboundedGrowth() async throws {
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: SessionAwareMessagesLoader(),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        for idx in 1...8 {
            await model.loadMessages(
                for: "session-\(idx)",
                serverURLString: "https://api.unhappy.im",
                token: "token"
            )
        }

        #expect(model.cachedSessionMessagesCount == 4)
    }

    @Test
    func loadMessagesTrimsPerSessionMessageCount() async throws {
        let overLimitMessages = (1...200).map { idx in
            APISessionMessage(
                id: "m\(idx)",
                seq: idx,
                localId: nil,
                content: APIEncryptedMessageContent(t: "encrypted", c: "\(idx)"),
                createdAt: TimeInterval(idx),
                updatedAt: TimeInterval(idx)
            )
        }
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success(overLimitMessages)),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.loadMessages(
            for: "session-over-limit",
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(model.selectedSessionMessages.count == 150)
        #expect(model.selectedSessionMessages.first?.seq == 51)
        #expect(model.selectedSessionMessages.last?.seq == 200)
    }

    @Test
    func loadMoreAppendsNextPageRows() async throws {
        let firstPageRows = [
            APISession(
                id: "s2",
                active: false,
                activeAt: 1,
                createdAt: 1,
                updatedAt: 20,
                metadataVersion: 1,
                metadata: "enc",
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let secondPageRows = [
            APISession(
                id: "s1",
                active: false,
                activeAt: 1,
                createdAt: 1,
                updatedAt: 10,
                metadataVersion: 1,
                metadata: "enc",
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let pageLoader = SequenceSessionsPageLoader(results: [
            .init(sessions: firstPageRows, nextCursor: "next", hasNext: true),
            .init(sessions: secondPageRows, nextCursor: nil, hasNext: false)
        ])
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success(firstPageRows)),
            pageLoader: pageLoader,
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([])),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.load(serverURLString: "https://api.unhappy.im", token: "token")
        await model.loadMoreSessions(serverURLString: "https://api.unhappy.im", token: "token")

        #expect(model.sessions.map(\.id) == ["s2", "s1"])
        #expect(model.hasMoreSessions == false)
    }

    @Test
    func setSessionTitleUpdatesSessionDisplayName() async throws {
        let sessions = [
            APISession(
                id: "session-1",
                active: false,
                activeAt: 1,
                createdAt: 1,
                updatedAt: 10,
                metadataVersion: 1,
                metadata: "enc",
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success(sessions)),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: sessions, nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([])),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.load(serverURLString: "https://api.unhappy.im", token: "token")
        await model.setSessionTitle(
            sessionID: "session-1",
            title: "New Title",
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(model.sessions.first?.displayName == "New Title")
        #expect(model.errorMessage == nil)
    }

    @Test
    func loadCodexThreadsPublishesRows() async throws {
        let expected = [
            APICodexThreadSummary(
                id: "thread-1",
                name: "Bugfix",
                cwd: "/tmp/project",
                updatedAt: "2026-02-24T10:00:00.000Z",
                createdAt: "2026-02-24T09:00:00.000Z",
                archived: false
            )
        ]
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([])),
            codexThreadsLoader: MockSessionCodexThreadsLoader(result: .success(expected)),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.loadCodexThreads(
            for: "session-1",
            serverURLString: "https://api.unhappy.im",
            token: "token",
            limit: 20
        )

        #expect(model.selectedCodexThreadsSessionID == "session-1")
        #expect(model.selectedCodexThreads == expected)
        #expect(model.selectedCodexThreadsErrorMessage == nil)
    }

    @Test
    func loadClaudeSessionsPublishesRows() async throws {
        let expected = [
            APIClaudeSessionSummary(
                id: "a1b2c3d4-1111-2222-3333-444444444444",
                cwd: "/tmp/project",
                updatedAt: "2026-02-24T10:00:00.000Z",
                createdAt: "2026-02-24T09:00:00.000Z"
            )
        ]
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([])),
            codexThreadsLoader: MockSessionCodexThreadsLoader(result: .success([])),
            claudeSessionsLoader: MockSessionClaudeSessionsLoader(result: .success(expected)),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.loadClaudeSessions(
            for: "session-1",
            serverURLString: "https://api.unhappy.im",
            token: "token",
            limit: 20
        )

        #expect(model.selectedClaudeSessionsSessionID == "session-1")
        #expect(model.selectedClaudeSessions == expected)
        #expect(model.selectedClaudeSessionsErrorMessage == nil)
    }
}

private enum MockSessionsLoaderError: Error, Sendable {
    case failed
}

private struct MockSessionsLoader: SessionsLoading {
    let result: Result<[APISession], MockSessionsLoaderError>

    func loadSessions(serverURLString: String, token: String) async throws -> [APISession] {
        switch result {
        case .success(let sessions):
            return sessions
        case .failure(let error):
            throw error
        }
    }
}

private struct MockSessionsServiceForValidation: SessionsFetching, SessionsPagingFetching, SessionMessagesFetching, SessionDeleting, SessionTitleUpdating, SessionCodexThreadsFetching, SessionClaudeSessionsFetching {
    func fetchSessions(serverURL: URL, token: String) async throws -> [APISession] {
        []
    }

    func fetchSessionsPage(serverURL: URL, token: String, cursor: String?, limit: Int) async throws -> APISessionsPage {
        APISessionsPage(sessions: [], nextCursor: nil, hasNext: false)
    }

    func fetchSessionMessages(serverURL: URL, token: String, sessionID: String) async throws -> [APISessionMessage] {
        []
    }

    func deleteSession(serverURL: URL, token: String, sessionID: String) async throws {}

    func setSessionTitle(serverURL: URL, token: String, sessionID: String, title: String?) async throws {}

    func fetchCodexThreads(serverURL: URL, token: String, sessionID: String, limit: Int, cwd: String?) async throws -> [APICodexThreadSummary] {
        []
    }

    func fetchClaudeSessions(serverURL: URL, token: String, sessionID: String, limit: Int, cwd: String?) async throws -> [APIClaudeSessionSummary] {
        []
    }
}

private struct MockSessionsPoller: SessionsPolling {
    let rows: [APISession]

    func makePollingStream(
        serverURLString: String,
        token: String,
        interval: Duration
    ) async -> AsyncThrowingStream<[APISession], Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(rows)
            continuation.finish()
        }
    }
}

private enum MockSessionsPageLoaderError: Error, Sendable {
    case failed
}

private struct MockSessionsPageLoader: SessionsPageLoading {
    let result: Result<SessionsPageResult, MockSessionsPageLoaderError>

    func loadPage(serverURLString: String, token: String, cursor: String?, limit: Int) async throws -> SessionsPageResult {
        switch result {
        case .success(let page):
            return page
        case .failure(let error):
            throw error
        }
    }
}

private actor SequenceSessionsPageLoader: SessionsPageLoading {
    private var pages: [SessionsPageResult]

    init(results: [SessionsPageResult]) {
        self.pages = results
    }

    func loadPage(serverURLString: String, token: String, cursor: String?, limit: Int) async throws -> SessionsPageResult {
        if pages.isEmpty {
            return SessionsPageResult(sessions: [], nextCursor: nil, hasNext: false)
        }
        return pages.removeFirst()
    }
}

private enum MockSessionsMessagesLoaderError: Error, Sendable {
    case failed
}

private struct MockSessionsMessagesLoader: SessionsMessagesLoading {
    let result: Result<[APISessionMessage], MockSessionsMessagesLoaderError>

    func loadMessages(serverURLString: String, token: String, sessionID: String) async throws -> [APISessionMessage] {
        switch result {
        case .success(let messages):
            return messages
        case .failure(let error):
            throw error
        }
    }
}

private struct SessionAwareMessagesLoader: SessionsMessagesLoading {
    func loadMessages(serverURLString: String, token: String, sessionID: String) async throws -> [APISessionMessage] {
        [
            APISessionMessage(
                id: "m-\(sessionID)",
                seq: 1,
                localId: nil,
                content: APIEncryptedMessageContent(t: "encrypted", c: "payload"),
                createdAt: 1,
                updatedAt: 1
            )
        ]
    }
}

private enum MockSessionDeleteUseCaseError: Error, Sendable {
    case failed
}

private struct MockSessionDeleteUseCase: SessionDeletingAction {
    let result: Result<Void, MockSessionDeleteUseCaseError>

    func deleteSession(serverURLString: String, token: String, sessionID: String) async throws {
        switch result {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }
}

private enum MockSessionTitleUseCaseError: Error, Sendable {
    case failed
}

private struct MockSessionTitleUseCase: SessionTitleUpdatingAction {
    let result: Result<Void, MockSessionTitleUseCaseError>

    func setSessionTitle(serverURLString: String, token: String, sessionID: String, title: String?) async throws {
        switch result {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }
}

private enum MockSessionCodexThreadsLoaderError: Error, Sendable {
    case failed
}

private struct MockSessionCodexThreadsLoader: SessionCodexThreadsLoading {
    let result: Result<[APICodexThreadSummary], MockSessionCodexThreadsLoaderError>

    func loadCodexThreads(serverURLString: String, token: String, sessionID: String, limit: Int, cwd: String?) async throws -> [APICodexThreadSummary] {
        switch result {
        case .success(let rows):
            return rows
        case .failure(let error):
            throw error
        }
    }
}

private enum MockSessionClaudeSessionsLoaderError: Error, Sendable {
    case failed
}

private struct MockSessionClaudeSessionsLoader: SessionClaudeSessionsLoading {
    let result: Result<[APIClaudeSessionSummary], MockSessionClaudeSessionsLoaderError>

    func loadClaudeSessions(serverURLString: String, token: String, sessionID: String, limit: Int, cwd: String?) async throws -> [APIClaudeSessionSummary] {
        switch result {
        case .success(let rows):
            return rows
        case .failure(let error):
            throw error
        }
    }
}
