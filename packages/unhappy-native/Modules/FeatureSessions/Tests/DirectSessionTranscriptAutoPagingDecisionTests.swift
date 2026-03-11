import Testing
@testable import FeatureSessions

struct DirectSessionTranscriptAutoPagingDecisionTests {
    @Test
    func doesNotAutoLoadWhileFollowingTranscript() {
        #expect(
            DirectSessionTranscriptAutoPagingDecision.shouldTrigger(
                currentTriggerID: "cursor-1",
                lastTriggeredID: nil,
                isTopPagingRowVisible: true,
                isNearTranscriptBottom: true,
                isLoadingOlderMessages: false
            ) == false
        )
    }

    @Test
    func doesNotAutoLoadSameCursorTwice() {
        #expect(
            DirectSessionTranscriptAutoPagingDecision.shouldTrigger(
                currentTriggerID: "cursor-1",
                lastTriggeredID: "cursor-1",
                isTopPagingRowVisible: true,
                isNearTranscriptBottom: false,
                isLoadingOlderMessages: false
            ) == false
        )
    }

    @Test
    func autoLoadsWhenUserReachedTopWithFreshCursor() {
        #expect(
            DirectSessionTranscriptAutoPagingDecision.shouldTrigger(
                currentTriggerID: "cursor-2",
                lastTriggeredID: "cursor-1",
                isTopPagingRowVisible: true,
                isNearTranscriptBottom: false,
                isLoadingOlderMessages: false
            ) == true
        )
    }
}
