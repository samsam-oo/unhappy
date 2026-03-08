import Testing
@testable import FeatureSessions

struct ProjectSyncStatusRowTests {
    @Test
    func refreshOnlyStateUsesCenteredLayoutWithSpinner() {
        let presentation = ProjectSyncStatusPresentation(
            isRefreshing: true,
            refreshLabel: "Refreshing projects…"
        )

        #expect(presentation.showsSpinner == true)
        #expect(presentation.primaryText == "Refreshing projects…")
    }

    @Test
    func idleStateShowsUpToDateMessageWithoutSpinner() {
        let presentation = ProjectSyncStatusPresentation(
            isRefreshing: false,
            refreshLabel: "Refreshing projects…"
        )

        #expect(presentation.showsSpinner == false)
        #expect(presentation.primaryText == "Projects are up to date")
    }
}
