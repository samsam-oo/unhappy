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
                    durationMs: 100,
                    supplementalEntries: []
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

        #expect(entries.map { $0.id } == ["tool-1"])
    }

    @Test
    func richEntriesCanFilterAcrossAbsoluteAndRelativePaths() {
        let matchingEntry = SessionTranscriptEntry(
            id: "match",
            role: .agent,
            kind: .toolCall,
            title: "Updated files",
            body: """
            {
              "changes": {
                "Sources/file.swift": {
                  "type": "update",
                  "move_path": null,
                  "unified_diff": "@@ -1 +1 @@\\n-old\\n+new"
                }
              },
              "auto_approved": false
            }
            """,
            toolUseID: "tool-1",
            sourceType: "tool-call",
            toolName: "codexpatch",
            isSidechain: false,
            threadID: nil
        )
        let otherEntry = SessionTranscriptEntry(
            id: "other",
            role: .agent,
            kind: .toolCall,
            title: "Updated files",
            body: """
            {
              "changes": {
                "Sources/other.swift": {
                  "type": "update",
                  "move_path": null,
                  "unified_diff": "@@ -1 +1 @@\\n-old\\n+new"
                }
              },
              "auto_approved": false
            }
            """,
            toolUseID: "tool-2",
            sourceType: "tool-call",
            toolName: "codexpatch",
            isSidechain: false,
            threadID: nil
        )
        let presentations = [
            SessionTranscriptMessagePresentation(
                messageID: "message-1",
                sequenceText: "1",
                createdAt: 1,
                createdAtText: "now",
                entries: [matchingEntry, otherEntry]
            )
        ]

        let entries = DirectSessionArtifacts.richEntries(
            from: presentations,
            matchingFilePath: "/tmp/project/Sources/file.swift"
        )

        #expect(entries.map { $0.id } == ["match"])
    }
}
