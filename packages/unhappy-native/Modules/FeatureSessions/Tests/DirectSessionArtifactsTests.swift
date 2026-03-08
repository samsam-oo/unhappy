import Testing
@testable import FeatureSessions

struct DirectSessionArtifactsTests {
    @Test
    func richEntriesCollectsOnlyRenderableToolArtifacts() {
        let richEntry = SessionTranscriptEntry(
            id: "tool-1",
            role: .agent,
            kind: .toolResult,
            title: "Updated files",
            body: SessionTranscriptRichContentParser.encodeCommandPayload(
                SessionTranscriptCommandExecutionPayload(
                    command: "git status",
                    cwd: "/tmp",
                    summary: "Explored 1 file",
                    logs: "done",
                    stdout: nil,
                    stderr: nil,
                    success: true,
                    exitCode: 0,
                    status: "completed",
                    durationMs: 100
                )
            ),
            toolUseID: "tool-1",
            sourceType: nil,
            toolName: "bash",
            isSidechain: false,
            threadID: nil
        )
        let plainEntry = SessionTranscriptEntry(
            id: "text-1",
            role: .agent,
            kind: .text,
            title: nil,
            body: "hello",
            toolUseID: nil,
            sourceType: nil,
            toolName: nil,
            isSidechain: false,
            threadID: nil
        )
        let presentations = [
            SessionTranscriptMessagePresentation(
                messageID: "message-1",
                sequenceText: "1",
                createdAt: 1,
                createdAtText: "now",
                entries: [richEntry, plainEntry]
            )
        ]

        let entries = DirectSessionArtifacts.richEntries(from: presentations)

        #expect(entries.map(\.id) == ["tool-1"])
    }
}
