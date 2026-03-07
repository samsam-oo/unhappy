import Foundation
import Testing
@testable import FeatureSessions
import CoreKit

struct SessionMessagesLoadUseCaseTests {
    @Test
    func loadMessagesThrowsMissingToken() async {
        let useCase = SessionMessagesLoadUseCase(service: ImmediateMessagesService(messages: []))

        await #expect(throws: SessionsMessagesLoadingError.missingToken) {
            _ = try await useCase.loadMessages(
                serverURLString: "https://api.unhappy.im",
                token: "   ",
                sessionID: "session-1"
            )
        }
    }

    @Test
    func loadMessagesThrowsMissingSessionID() async {
        let useCase = SessionMessagesLoadUseCase(service: ImmediateMessagesService(messages: []))

        await #expect(throws: SessionsMessagesLoadingError.missingSessionID) {
            _ = try await useCase.loadMessages(
                serverURLString: "https://api.unhappy.im",
                token: "token",
                sessionID: " "
            )
        }
    }

    @Test
    func loadMessagesReturnsRowsSortedBySequence() async throws {
        let rows = [
            APISessionMessage(
                id: "m2",
                seq: 2,
                localId: nil,
                content: APIEncryptedMessageContent(type: "encrypted", payload: "2"),
                createdAt: 20,
                updatedAt: 20
            ),
            APISessionMessage(
                id: "m1",
                seq: 1,
                localId: nil,
                content: APIEncryptedMessageContent(type: "encrypted", payload: "1"),
                createdAt: 10,
                updatedAt: 10
            )
        ]
        let useCase = SessionMessagesLoadUseCase(service: ImmediateMessagesService(messages: rows))

        let loaded = try await useCase.loadMessages(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            sessionID: "session-1"
        )

        #expect(loaded.map(\.id) == ["m1", "m2"])
    }

    @Test
    func concurrentLoadsShareSingleInFlightRequest() async throws {
        let rows = [
            APISessionMessage(
                id: "m1",
                seq: 1,
                localId: nil,
                content: nil,
                createdAt: 1,
                updatedAt: 1
            )
        ]
        let service = SlowCountingMessagesService(messages: rows)
        let useCase = SessionMessagesLoadUseCase(service: service)

        async let first = useCase.loadMessages(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            sessionID: "session-1"
        )
        async let second = useCase.loadMessages(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            sessionID: "session-1"
        )

        let firstRows = try await first
        let secondRows = try await second

        #expect(firstRows == secondRows)
        #expect(await service.fetchCount() == 1)
    }
}

private struct ImmediateMessagesService: SessionMessagesFetching {
    let messages: [APISessionMessage]

    func fetchSessionMessages(serverURL: URL, token: String, sessionID: String) async throws -> [APISessionMessage] {
        messages
    }
}

private actor SlowCountingMessagesService: SessionMessagesFetching {
    private let messages: [APISessionMessage]
    private var count: Int = 0

    init(messages: [APISessionMessage]) {
        self.messages = messages
    }

    func fetchSessionMessages(serverURL: URL, token: String, sessionID: String) async throws -> [APISessionMessage] {
        count += 1
        try await Task.sleep(nanoseconds: 80_000_000)
        return messages
    }

    func fetchCount() -> Int {
        count
    }
}
