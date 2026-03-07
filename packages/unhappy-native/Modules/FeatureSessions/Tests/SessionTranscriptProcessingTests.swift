import Foundation
import Testing
@testable import FeatureSessions

struct SessionTranscriptProcessingTests {
    @Test
    func coalescesCommandEntriesIntoSingleCommandCard() {
        let presentations = makeCommandPresentations()

        let coalesced = SessionTranscriptProcessing.coalesceStreamingEntries(in: presentations)

        #expect(coalesced.count == 1)
        #expect(coalesced[0].entries.count == 1)

        let entry = coalesced[0].entries[0]
        #expect(entry.kind == .toolResult)
        #expect(entry.title == "Ran command")

        guard case .commandExecution(let command)? = SessionTranscriptRichContentParser.richToolContent(for: entry) else {
            Issue.record("Expected a command execution card")
            return
        }

        #expect(command.command == "corepack yarn test")
        #expect(command.summary == "Explored 1 file, 1 search")
        #expect(command.logs == "running tests")
        #expect(command.status == .succeeded)
        #expect(command.exitCode == 0)
        #expect(command.durationText == "11s")
    }

    private func makeCommandPresentations() -> [SessionTranscriptMessagePresentation] {
        let commandBody = """
        {"command":"corepack yarn test","cwd":"/tmp/project","commandActions":[{"type":"read","path":"README.md"},{"type":"search","query":"TODO"}]}
        """
        let callEntry = makeEntry(
            id: "call",
            kind: .toolCall,
            title: "Command Execution",
            body: commandBody,
            sourceType: "item_started"
        )
        let outputEntry = makeEntry(
            id: "output",
            kind: .raw,
            title: "Streaming output",
            body: "running tests\n",
            sourceType: "terminal-output",
            toolName: nil
        )
        let resultEntry = makeEntry(
            id: "result",
            kind: .toolResult,
            title: "Command Result",
            body: #"{"success":true,"exitCode":0}"#,
            sourceType: "item_completed"
        )

        return [
            makePresentation(messageID: "msg-1", sequenceText: "1", createdAt: 100, createdAtText: "10:00", entry: callEntry),
            makePresentation(messageID: "msg-2", sequenceText: "2", createdAt: 104, createdAtText: "10:04", entry: outputEntry),
            makePresentation(messageID: "msg-3", sequenceText: "3", createdAt: 111, createdAtText: "10:11", entry: resultEntry)
        ]
    }

    private func makeEntry(
        id: String,
        kind: SessionTranscriptEntryKind,
        title: String,
        body: String,
        sourceType: String,
        toolName: String? = "codexbash"
    ) -> SessionTranscriptEntry {
        SessionTranscriptEntry(
            id: id,
            role: .agent,
            kind: kind,
            title: title,
            body: body,
            toolUseID: "cmd_1",
            sourceType: sourceType,
            toolName: toolName,
            isSidechain: false,
            threadID: nil
        )
    }

    private func makePresentation(
        messageID: String,
        sequenceText: String,
        createdAt: TimeInterval,
        createdAtText: String,
        entry: SessionTranscriptEntry
    ) -> SessionTranscriptMessagePresentation {
        SessionTranscriptMessagePresentation(
            messageID: messageID,
            sequenceText: sequenceText,
            createdAt: createdAt,
            createdAtText: createdAtText,
            entries: [entry]
        )
    }
}
