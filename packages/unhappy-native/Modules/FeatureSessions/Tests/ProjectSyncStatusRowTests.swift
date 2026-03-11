import Testing
@testable import FeatureSessions

struct ProjectSyncStatusRowTests {
    @Test
    func refreshOnlyStateUsesCenteredLayoutWithSpinner() {
        let presentation = ProjectSyncStatusPresentation(
            multiAgentInProgressCount: 0,
            isRefreshing: true,
            refreshLabel: "Refreshing projects…",
            reconnectingStatusText: nil
        )

        #expect(presentation.layout == .centered)
        #expect(presentation.showsSpinner == true)
        #expect(presentation.primaryText == "Refreshing projects…")
    }

    @Test
    func idleStateShowsUpToDateMessageWithoutSpinner() {
        let presentation = ProjectSyncStatusPresentation(
            multiAgentInProgressCount: 0,
            isRefreshing: false,
            refreshLabel: "Refreshing projects…",
            reconnectingStatusText: nil
        )

        #expect(presentation.showsSpinner == false)
        #expect(presentation.primaryText == "Projects are up to date")
    }

    @Test
    func multiAgentStateUsesLeadingLayout() {
        let presentation = ProjectSyncStatusPresentation(
            multiAgentInProgressCount: 2,
            isRefreshing: true,
            refreshLabel: "Refreshing projects…",
            reconnectingStatusText: nil
        )

        #expect(presentation.layout == .leading)
        #expect(presentation.showsSpinner == true)
        #expect(presentation.primaryText == "2 multi-agent tasks")
        #expect(presentation.secondaryText == "Refreshing projects…")
        #expect(presentation.multiAgentStatus?.state == .inProgress)
    }

    @Test
    func reconnectingStateUsesCenteredSpinnerWhenNoMultiAgentWorkExists() {
        let presentation = ProjectSyncStatusPresentation(
            multiAgentInProgressCount: 0,
            isRefreshing: false,
            refreshLabel: "Refreshing projects…",
            reconnectingStatusText: "Reconnecting to machine…"
        )

        #expect(presentation.layout == .centered)
        #expect(presentation.showsSpinner == true)
        #expect(presentation.primaryText == "Reconnecting to machine…")
    }
}
