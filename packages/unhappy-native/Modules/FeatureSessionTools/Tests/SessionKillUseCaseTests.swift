import Foundation
import Testing
@testable import FeatureSessionTools
import CoreKit

struct SessionKillUseCaseTests {
    @Test
    func killSessionThrowsMissingToken() async {
        let useCase = SessionKillUseCase(
            service: ImmediateKillService(result: .init(success: true, message: "ok"))
        )

        await #expect(throws: SessionKillError.missingToken) {
            _ = try await useCase.killSession(
                serverURLString: "https://api.unhappy.im",
                token: " ",
                sessionID: "session-1"
            )
        }
    }

    @Test
    func killSessionReturnsResultWhenSuccessful() async throws {
        let useCase = SessionKillUseCase(
            service: ImmediateKillService(result: .init(success: true, message: "Session killed"))
        )

        let result = try await useCase.killSession(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            sessionID: "session-1"
        )

        #expect(result.success == true)
        #expect(result.message == "Session killed")
    }

    @Test
    func killSessionThrowsWhenServiceReturnsFailure() async {
        let useCase = SessionKillUseCase(
            service: ImmediateKillService(result: .init(success: false, message: "not connected"))
        )

        await #expect(throws: SessionKillError.failed(message: "not connected")) {
            _ = try await useCase.killSession(
                serverURLString: "https://api.unhappy.im",
                token: "token",
                sessionID: "session-1"
            )
        }
    }

    @Test
    func concurrentKillsShareSingleInFlightRequest() async throws {
        let service = SlowCountingKillService(result: .init(success: true, message: "ok"))
        let useCase = SessionKillUseCase(service: service)

        async let first = useCase.killSession(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            sessionID: "session-1"
        )
        async let second = useCase.killSession(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            sessionID: "session-1"
        )

        _ = try await first
        _ = try await second

        #expect(await service.fetchCount() == 1)
    }
}

private struct ImmediateKillService: SessionKilling {
    let result: APISessionKillResult

    func killSession(serverURL: URL, token: String, sessionID: String) async throws -> APISessionKillResult {
        result
    }
}

private actor SlowCountingKillService: SessionKilling {
    private let result: APISessionKillResult
    private var count: Int = 0

    init(result: APISessionKillResult) {
        self.result = result
    }

    func killSession(serverURL: URL, token: String, sessionID: String) async throws -> APISessionKillResult {
        count += 1
        try await Task.sleep(nanoseconds: 80_000_000)
        return result
    }

    func fetchCount() -> Int {
        count
    }
}
