import Testing
@testable import FeatureSettings

@MainActor
struct UsageSettingsViewModelTests {
    @Test
    func loadUsagePublishesSnapshot() async {
        let viewModel = UsageSettingsViewModel(
            usageLoader: UsageLoader(
                result: .success(
                    SettingsUsageSnapshot(
                        totalSessions: 3,
                        activeSessions: 1,
                        inactiveSessions: 2,
                        lastUpdatedAt: 123
                    )
                )
            )
        )

        await viewModel.loadUsage(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(viewModel.snapshot?.totalSessions == 3)
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func loadUsagePublishesError() async {
        let viewModel = UsageSettingsViewModel(
            usageLoader: UsageLoader(
                result: .failure(SettingsUsageError.missingToken)
            )
        )

        await viewModel.loadUsage(
            serverURLString: "https://api.unhappy.im",
            token: " "
        )

        #expect(viewModel.snapshot == nil)
        #expect(viewModel.errorMessage == "API token is required")
    }
}

private struct UsageLoader: SettingsUsageLoadingAction {
    let result: Result<SettingsUsageSnapshot, Error>

    func loadUsage(serverURLString: String, token: String) async throws -> SettingsUsageSnapshot {
        try result.get()
    }
}
