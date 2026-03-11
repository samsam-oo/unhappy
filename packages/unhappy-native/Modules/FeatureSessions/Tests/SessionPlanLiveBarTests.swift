import Testing
import SessionKit
@testable import FeatureSessions

struct SessionPlanLiveBarTests {
    @Test
    func latestPlanPrefersNewestPlanAndUsesInProgressStep() {
        let olderPlan = SessionTranscriptEntry(
            id: "plan-old",
            role: .agent,
            kind: .toolResult,
            title: "update_plan",
            body: """
            {
              "plan": [
                { "step": "Older step", "status": "completed" }
              ]
            }
            """,
            toolUseID: "plan-1",
            sourceType: "tool_result",
            toolName: "update_plan",
            isSidechain: false,
            threadID: nil
        )
        let latestPlan = SessionTranscriptEntry(
            id: "plan-new",
            role: .agent,
            kind: .toolResult,
            title: "update_plan",
            body: """
            {
              "explanation": "Do the active work first.",
              "plan": [
                { "step": "Inspect logs", "status": "completed" },
                { "step": "Patch reconnect flow", "status": "in_progress" },
                { "step": "Verify", "status": "pending" }
              ]
            }
            """,
            toolUseID: "plan-2",
            sourceType: "tool_result",
            toolName: "update_plan",
            isSidechain: false,
            threadID: nil
        )

        let presentation = SessionPlanLivePresentationBuilder.latestPlan(
            in: [
                SessionTranscriptMessagePresentation(
                    messageID: "msg-1",
                    sequenceText: "1",
                    createdAt: 1,
                    createdAtText: "10:00",
                    entries: [olderPlan]
                ),
                SessionTranscriptMessagePresentation(
                    messageID: "msg-2",
                    sequenceText: "2",
                    createdAt: 2,
                    createdAtText: "10:01",
                    entries: [latestPlan]
                ),
            ]
        )

        #expect(presentation?.title == "Plan · 3 steps")
        #expect(presentation?.status == .inProgress)
        #expect(presentation?.subtitle == "Patch reconnect flow")
    }
}
