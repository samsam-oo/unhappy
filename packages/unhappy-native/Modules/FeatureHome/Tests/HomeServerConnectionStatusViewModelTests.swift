import Foundation
import Testing
@testable import FeatureHome

@MainActor
struct HomeServerConnectionStatusViewModelTests {
    @Test
    func refreshPublishesConnectedStatus() async {
        let viewModel = HomeServerConnectionStatusViewModel(
            loader: HomeServerStatusLoader(status: .connected)
        )

        await viewModel.refresh(serverURLString: "https://api.unhappy.im")

        #expect(viewModel.status == .connected)
        #expect(viewModel.isLoading == false)
    }

    @Test
    func refreshPublishesConnectingWhileLoading() async {
        let viewModel = HomeServerConnectionStatusViewModel(
            loader: DelayedHomeServerStatusLoader(status: .disconnected)
        )

        let task = Task {
            await viewModel.refresh(serverURLString: "https://api.unhappy.im")
        }
        await Task.yield()

        #expect(viewModel.status == .connecting)

        await task.value
        #expect(viewModel.status == .disconnected)
        #expect(viewModel.isLoading == false)
    }
}

private struct HomeServerStatusLoader: HomeServerConnectionStatusLoadingAction {
    let status: HomeServerConnectionStatus

    func loadStatus(serverURLString: String) async -> HomeServerConnectionStatus {
        status
    }
}

private struct DelayedHomeServerStatusLoader: HomeServerConnectionStatusLoadingAction {
    let status: HomeServerConnectionStatus

    func loadStatus(serverURLString: String) async -> HomeServerConnectionStatus {
        try? await Task.sleep(for: .milliseconds(30))
        return status
    }
}
