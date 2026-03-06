import Foundation
import Testing
@testable import FeatureSessions
import CoreKit

struct SessionsPollingUseCaseTests {
    @Test
    func pollingStreamEmitsSortedRows() async throws {
        let rows = [
            APISession(
                id: "old",
                active: true,
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
                active: true,
                activeAt: 1,
                createdAt: 1,
                updatedAt: 20,
                metadataVersion: 1,
                metadata: "enc",
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let useCase = SessionsPollingUseCase(
            loader: ImmediateSessionsLoader(result: .success(rows))
        )

        let stream = await useCase.makePollingStream(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            interval: .seconds(60)
        )
        var iterator = stream.makeAsyncIterator()

        let first = try await iterator.next()
        #expect(first?.map(\.id) == ["new", "old"])
    }

    @Test
    func pollingStreamPropagatesErrors() async {
        let useCase = SessionsPollingUseCase(
            loader: ImmediateSessionsLoader(result: .failure(SessionsLoadingError.missingToken))
        )

        let stream = await useCase.makePollingStream(
            serverURLString: "https://api.unhappy.im",
            token: "",
            interval: .seconds(60)
        )

        await #expect(throws: SessionsLoadingError.missingToken) {
            var iterator = stream.makeAsyncIterator()
            _ = try await iterator.next()
        }
    }

    @Test
    func pollingStreamUsesFastIntervalWhileSessionsAreActive() async throws {
        let rows = [
            APISession(
                id: "active",
                active: true,
                activeAt: 1,
                createdAt: 1,
                updatedAt: 20,
                metadataVersion: 1,
                metadata: "enc",
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let useCase = SessionsPollingUseCase(
            loader: ImmediateSessionsLoader(result: .success(rows)),
            activeInterval: .milliseconds(20)
        )

        let stream = await useCase.makePollingStream(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            interval: .seconds(60)
        )
        var iterator = stream.makeAsyncIterator()

        _ = try await iterator.next()
        let clock = ContinuousClock()
        let start = clock.now
        let second = try await iterator.next()
        let elapsed = start.duration(to: clock.now)

        #expect(second?.map(\.id) == ["active"])
        #expect(elapsed < .seconds(1))
    }
}

private struct ImmediateSessionsLoader: SessionsLoading {
    let result: Result<[APISession], SessionsLoadingError>

    func loadSessions(serverURLString: String, token: String) async throws -> [APISession] {
        switch result {
        case .success(let rows):
            return rows
        case .failure(let error):
            throw error
        }
    }
}
