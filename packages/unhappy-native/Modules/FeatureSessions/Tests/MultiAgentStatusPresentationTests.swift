import Testing
@testable import FeatureSessions

struct MultiAgentStatusPresentationTests {
    @Test
    func builderUsesInProgressStateAndPluralSummary() {
        let presentation = MultiAgentStatusPresentationBuilder.make(
            activeSessionsCount: 3,
            inProgress: true
        )

        #expect(presentation.summaryText == "3 active sessions")
        #expect(presentation.statusText == "진행중")
        #expect(presentation.symbolName == "bolt.fill")
        #expect(presentation.state == .inProgress)
    }

    @Test
    func builderUsesCompletedStateAndSingularSummary() {
        let presentation = MultiAgentStatusPresentationBuilder.make(
            activeSessionsCount: 1,
            inProgress: false
        )

        #expect(presentation.summaryText == "1 active session")
        #expect(presentation.statusText == "완료됨")
        #expect(presentation.symbolName == "checkmark.circle")
        #expect(presentation.state == .completed)
    }

    @Test
    func builderNormalizesNegativeCountsToZero() {
        let presentation = MultiAgentStatusPresentationBuilder.make(
            activeSessionsCount: -10,
            inProgress: false
        )

        #expect(presentation.summaryText == "No active sessions")
    }
}
