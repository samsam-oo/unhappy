import Testing
@testable import FeatureSessions

struct MultiAgentStatusPresentationTests {
    @Test
    func builderUsesInProgressStateAndPluralSummary() {
        let presentation = MultiAgentStatusPresentationBuilder.make(
            inProgressCount: 3
        )

        #expect(presentation?.summaryText == "3 multi-agent tasks")
        #expect(presentation?.statusText == "진행중")
        #expect(presentation?.symbolName == "bolt.fill")
        #expect(presentation?.state == .inProgress)
    }

    @Test
    func builderUsesSingularSummary() {
        let presentation = MultiAgentStatusPresentationBuilder.make(
            inProgressCount: 1
        )

        #expect(presentation?.summaryText == "1 multi-agent task")
    }

    @Test
    func builderReturnsNilForZeroOrNegativeCounts() {
        #expect(MultiAgentStatusPresentationBuilder.make(inProgressCount: 0) == nil)
        #expect(MultiAgentStatusPresentationBuilder.make(inProgressCount: -10) == nil)
    }
}
