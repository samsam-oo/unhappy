import Foundation
import Testing
@testable import FeatureSessions
import CoreKit
import SessionKit

struct SessionDeleteUseCaseTests {
    @Test
    func deleteSessionThrowsMissingToken() async {
        let useCase = SessionDeleteUseCase(service: NoopSessionDeleteService())

        await #expect(throws: SessionDeleteError.missingToken) {
            try await useCase.deleteSession(
                serverURLString: "https://api.unhappy.im",
                token: " ",
                sessionID: "session-1"
            )
        }
    }

    @Test
    func deleteSessionThrowsInvalidServerURL() async {
        let useCase = SessionDeleteUseCase(service: NoopSessionDeleteService())

        await #expect(throws: SessionDeleteError.invalidServerURL) {
            try await useCase.deleteSession(
                serverURLString: "invalid-url",
                token: "token",
                sessionID: "session-1"
            )
        }
    }

    @Test
    func deleteSessionThrowsMissingSessionID() async {
        let useCase = SessionDeleteUseCase(service: NoopSessionDeleteService())

        await #expect(throws: SessionDeleteError.missingSessionID) {
            try await useCase.deleteSession(
                serverURLString: "https://api.unhappy.im",
                token: "token",
                sessionID: " "
            )
        }
    }

    @Test
    func concurrentDeletesShareSingleInFlightRequest() async throws {
        let service = SlowCountingDeleteService()
        let useCase = SessionDeleteUseCase(service: service)

        async let first: Void = useCase.deleteSession(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            sessionID: "session-1"
        )
        async let second: Void = useCase.deleteSession(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            sessionID: "session-1"
        )

        _ = try await first
        _ = try await second

        #expect(await service.deleteCount() == 1)
    }
}

private struct NoopSessionDeleteService: SessionDeleting {
    func deleteSession(serverURL: URL, token: String, sessionID: String) async throws {}
}

private actor SlowCountingDeleteService: SessionDeleting {
    private var count: Int = 0

    func deleteSession(serverURL: URL, token: String, sessionID: String) async throws {
        count += 1
        try await Task.sleep(nanoseconds: 80_000_000)
    }

    func deleteCount() -> Int {
        count
    }
}
