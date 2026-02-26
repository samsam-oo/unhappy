import Foundation
import Testing
@testable import FeatureHome

struct HomeServerConnectionStatusUseCaseTests {
    @Test
    func loadStatusReturnsDisconnectedForInvalidServerURL() async {
        let checker = MockHomeServerHealthChecker(reachable: true)
        let useCase = HomeServerConnectionStatusLoadUseCase(healthChecker: checker)

        let status = await useCase.loadStatus(serverURLString: "not-a-url")

        #expect(status == .disconnected)
        #expect(await checker.lastServerURL == nil)
    }

    @Test
    func loadStatusReturnsConnectedWhenServerIsReachable() async {
        let checker = MockHomeServerHealthChecker(reachable: true)
        let useCase = HomeServerConnectionStatusLoadUseCase(healthChecker: checker)

        let status = await useCase.loadStatus(serverURLString: " https://api.unhappy.im ")

        #expect(status == .connected)
        #expect(await checker.lastServerURL?.absoluteString == "https://api.unhappy.im")
    }

    @Test
    func loadStatusReturnsDisconnectedWhenServerIsNotReachable() async {
        let checker = MockHomeServerHealthChecker(reachable: false)
        let useCase = HomeServerConnectionStatusLoadUseCase(healthChecker: checker)

        let status = await useCase.loadStatus(serverURLString: "https://api.unhappy.im")

        #expect(status == .disconnected)
    }

    @Test
    func loadStatusReturnsDisconnectedWhenHealthCheckThrows() async {
        let checker = MockHomeServerHealthChecker(
            reachable: false,
            error: URLError(.cannotFindHost)
        )
        let useCase = HomeServerConnectionStatusLoadUseCase(healthChecker: checker)

        let status = await useCase.loadStatus(serverURLString: "https://api.unhappy.im")

        #expect(status == .disconnected)
    }
}

private actor MockHomeServerHealthChecker: HomeServerHealthChecking {
    private(set) var lastServerURL: URL?
    let reachable: Bool
    let error: Error?

    init(reachable: Bool, error: Error? = nil) {
        self.reachable = reachable
        self.error = error
    }

    func checkReachable(serverURL: URL) async throws -> Bool {
        lastServerURL = serverURL
        if let error {
            throw error
        }
        return reachable
    }
}
