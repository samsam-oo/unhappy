import Foundation
import Testing
@testable import FeatureSessions
import CoreKit

struct SessionTitleUpdateUseCaseTests {
    @Test
    func setSessionTitleThrowsMissingToken() async {
        let useCase = SessionTitleUpdateUseCase(service: NoopSessionTitleService())

        await #expect(throws: SessionTitleUpdateError.missingToken) {
            try await useCase.setSessionTitle(
                serverURLString: "https://api.unhappy.im",
                token: " ",
                sessionID: "session-1",
                title: "Title"
            )
        }
    }

    @Test
    func setSessionTitleThrowsMissingSessionID() async {
        let useCase = SessionTitleUpdateUseCase(service: NoopSessionTitleService())

        await #expect(throws: SessionTitleUpdateError.missingSessionID) {
            try await useCase.setSessionTitle(
                serverURLString: "https://api.unhappy.im",
                token: "token",
                sessionID: "",
                title: "Title"
            )
        }
    }

    @Test
    func concurrentRenamesShareSingleInFlightRequest() async throws {
        let service = SlowCountingTitleService()
        let useCase = SessionTitleUpdateUseCase(service: service)

        async let first: Void = useCase.setSessionTitle(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            sessionID: "session-1",
            title: "My Session"
        )
        async let second: Void = useCase.setSessionTitle(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            sessionID: "session-1",
            title: "My Session"
        )

        _ = try await first
        _ = try await second

        #expect(await service.updateCount() == 1)
    }
}

private struct NoopSessionTitleService: SessionTitleUpdating {
    func setSessionTitle(serverURL: URL, token: String, sessionID: String, title: String?) async throws {}
}

private actor SlowCountingTitleService: SessionTitleUpdating {
    private var count: Int = 0

    func setSessionTitle(serverURL: URL, token: String, sessionID: String, title: String?) async throws {
        count += 1
        try await Task.sleep(nanoseconds: 80_000_000)
    }

    func updateCount() -> Int {
        count
    }
}
