import Testing
@testable import FeatureSessions

struct ProjectSyncStatusRowTests {
    @Test
    func refreshOnlyStateUsesCenteredLayoutWithSpinner() {
        let presentation = ProjectSyncStatusPresentation(
            activeSessionsCount: 0,
            isRefreshing: true,
            refreshLabel: "Refreshing projects…"
        )

        #expect(presentation.layout == .centered)
        #expect(presentation.showsSpinner == true)
        #expect(presentation.primaryText == "Refreshing projects…")
        #expect(presentation.secondaryText == nil)
    }

    @Test
    func activeSessionsStateUsesLeadingLayout() {
        let presentation = ProjectSyncStatusPresentation(
            activeSessionsCount: 2,
            isRefreshing: true,
            refreshLabel: "Refreshing projects…"
        )

        #expect(presentation.layout == .leading)
        #expect(presentation.showsSpinner == true)
        #expect(presentation.primaryText == "2 active sessions")
        #expect(presentation.secondaryText == "Refreshing projects…")
    }
}
