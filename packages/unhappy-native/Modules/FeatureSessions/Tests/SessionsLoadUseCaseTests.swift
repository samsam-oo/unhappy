import Foundation
import Testing
@testable import FeatureSessions
import CoreKit

struct SessionsLoadUseCaseTests {
    @Test
    func loadSessionsThrowsMissingToken() async {
        let useCase = SessionsLoadUseCase(service: ImmediateSessionsService(sessions: []))

        await #expect(throws: SessionsLoadingError.missingToken) {
            _ = try await useCase.loadSessions(
                serverURLString: "https://api.unhappy.im",
                token: "   "
            )
        }
    }

    @Test
    func loadSessionsThrowsInvalidServerURL() async {
        let useCase = SessionsLoadUseCase(service: ImmediateSessionsService(sessions: []))

        await #expect(throws: SessionsLoadingError.invalidServerURL) {
            _ = try await useCase.loadSessions(
                serverURLString: "not-a-url",
                token: "token"
            )
        }
    }

    @Test
    func loadSessionsReturnsSortedRows() async throws {
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
                updatedAt: 30,
                metadataVersion: 1,
                metadata: "enc",
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let useCase = SessionsLoadUseCase(service: ImmediateSessionsService(sessions: rows))

        let loaded = try await useCase.loadSessions(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(loaded.map(\.id) == ["new", "old"])
    }

    @Test
    func loadSessionsFiltersArchivedRows() async throws {
        let rows = [
            APISession(
                id: "archived",
                active: false,
                activeAt: 1,
                createdAt: 1,
                updatedAt: 40,
                archived: true,
                metadataVersion: 1,
                metadata: "enc",
                dataEncryptionKey: nil,
                lastMessage: nil
            ),
            APISession(
                id: "visible",
                active: true,
                activeAt: 1,
                createdAt: 1,
                updatedAt: 30,
                archived: false,
                metadataVersion: 1,
                metadata: "enc",
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let useCase = SessionsLoadUseCase(service: ImmediateSessionsService(sessions: rows))

        let loaded = try await useCase.loadSessions(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(loaded.map { $0.id } == ["visible"])
    }

    @Test
    func concurrentLoadsShareSingleInFlightRequest() async throws {
        let rows = [
            APISession(
                id: "one",
                active: true,
                activeAt: 1,
                createdAt: 1,
                updatedAt: 30,
                metadataVersion: 1,
                metadata: "enc",
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let service = SlowCountingSessionsService(sessions: rows)
        let useCase = SessionsLoadUseCase(service: service)

        async let first = useCase.loadSessions(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )
        async let second = useCase.loadSessions(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        let firstRows = try await first
        let secondRows = try await second

        #expect(firstRows == secondRows)
        #expect(await service.fetchCount() == 1)
    }
}

private struct ImmediateSessionsService: SessionsFetching {
    let sessions: [APISession]

    func fetchSessions(serverURL: URL, token: String) async throws -> [APISession] {
        sessions
    }
}

private actor SlowCountingSessionsService: SessionsFetching {
    private let sessions: [APISession]
    private var count: Int = 0

    init(sessions: [APISession]) {
        self.sessions = sessions
    }

    func fetchSessions(serverURL: URL, token: String) async throws -> [APISession] {
        count += 1
        try await Task.sleep(nanoseconds: 80_000_000)
        return sessions
    }

    func fetchCount() -> Int {
        count
    }
}
