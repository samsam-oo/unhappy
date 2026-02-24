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
            poller: MockSessionsPoller(rows: [])
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
            poller: MockSessionsPoller(rows: [])
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
            poller: MockSessionsPoller(rows: expected)
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

private struct MockSessionsServiceForValidation: SessionsFetching {
    func fetchSessions(serverURL: URL, token: String) async throws -> [APISession] {
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
