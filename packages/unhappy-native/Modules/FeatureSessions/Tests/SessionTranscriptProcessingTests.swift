import Foundation
import Testing
@testable import FeatureSessions
import SessionKit

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

    @Test
    func coalescesCommandEntriesWithoutMatchingToolUseIDWhenOnlyOneCommandIsOpen() {
        let commandBody = """
        {"command":"swift test","cwd":"/tmp/project"}
        """
        let callEntry = makeEntry(
            id: "call-single",
            kind: .toolCall,
            title: "Command Execution",
            body: commandBody,
            sourceType: "item_started"
        )
        let outputEntry = SessionTranscriptEntry(
            id: "output-single",
            role: .agent,
            kind: .raw,
            title: "Streaming output",
            body: "collecting logs\n",
            toolUseID: nil,
            sourceType: "terminal-output",
            toolName: nil,
            isSidechain: false,
            threadID: nil
        )
        let resultEntry = SessionTranscriptEntry(
            id: "result-single",
            role: .agent,
            kind: .toolResult,
            title: "Command Result",
            body: #"{"success":true,"exitCode":0}"#,
            toolUseID: nil,
            sourceType: "item_completed",
            toolName: "codexbash",
            isSidechain: false,
            threadID: nil
        )

        let coalesced = SessionTranscriptProcessing.coalesceStreamingEntries(in: [
            makePresentation(messageID: "msg-1", sequenceText: "1", createdAt: 100, createdAtText: "10:00", entry: callEntry),
            makePresentation(messageID: "msg-2", sequenceText: "2", createdAt: 101, createdAtText: "10:01", entry: outputEntry),
            makePresentation(messageID: "msg-3", sequenceText: "3", createdAt: 102, createdAtText: "10:02", entry: resultEntry),
        ])

        guard case .commandExecution(let command)? =
                SessionTranscriptRichContentParser.richToolContent(for: coalesced[0].entries[0]) else {
            Issue.record("Expected a command execution card")
            return
        }

        #expect(command.logs == "collecting logs")
        #expect(command.status == .succeeded)
    }

    @Test
    func taskCompleteFinalizesOpenCommandWithoutExplicitToolResult() {
        let callEntry = makeEntry(
            id: "call-open",
            kind: .toolCall,
            title: "Command Execution",
            body: #"{"command":"npm test","cwd":"/tmp/project"}"#,
            sourceType: "item_started"
        )
        let outputEntry = makeEntry(
            id: "output-open",
            kind: .raw,
            title: "Streaming output",
            body: "running\n",
            sourceType: "terminal-output",
            toolName: nil
        )
        let completeEntry = SessionTranscriptEntry(
            id: "task-complete",
            role: .system,
            kind: .event,
            title: "Task Complete",
            body: "done",
            toolUseID: nil,
            sourceType: "task_complete",
            toolName: nil,
            isSidechain: false,
            threadID: nil
        )

        let coalesced = SessionTranscriptProcessing.coalesceStreamingEntries(in: [
            makePresentation(messageID: "msg-1", sequenceText: "1", createdAt: 100, createdAtText: "10:00", entry: callEntry),
            makePresentation(messageID: "msg-2", sequenceText: "2", createdAt: 104, createdAtText: "10:04", entry: outputEntry),
            makePresentation(messageID: "msg-3", sequenceText: "3", createdAt: 111, createdAtText: "10:11", entry: completeEntry),
        ])

        guard case .commandExecution(let command)? =
                SessionTranscriptRichContentParser.richToolContent(for: coalesced[0].entries[0]) else {
            Issue.record("Expected a command execution card")
            return
        }

        #expect(command.status == .succeeded)
        #expect(command.logs == "running")
        #expect(command.durationText == "11s")
    }

    @Test
    func plainExecCommandToolResultFinalizesCommandCard() {
        let callEntry = makeEntry(
            id: "exec-call",
            kind: .toolCall,
            title: "Ran command",
            body: #"{"command":"git status","cwd":"/tmp/project"}"#,
            sourceType: "tool-call",
            toolName: "exec_command"
        )
        let resultEntry = makeEntry(
            id: "exec-result",
            kind: .toolResult,
            title: "Ran command Result",
            body: "Process exited with code 0",
            sourceType: "tool_result",
            toolName: "exec_command"
        )

        let coalesced = SessionTranscriptProcessing.coalesceStreamingEntries(in: [
            makePresentation(messageID: "msg-1", sequenceText: "1", createdAt: 100, createdAtText: "10:00", entry: callEntry),
            makePresentation(messageID: "msg-2", sequenceText: "2", createdAt: 108, createdAtText: "10:08", entry: resultEntry),
        ])

        guard case .commandExecution(let command)? =
                SessionTranscriptRichContentParser.richToolContent(for: coalesced[0].entries[0]) else {
            Issue.record("Expected command execution card")
            return
        }

        #expect(command.status == .succeeded)
        #expect(command.supplementalEntries.map(\.title) == ["Ran command Result"])
    }

    @Test
    func writeStdinEventsAreNestedInsideOpenCommandCard() {
        let callEntry = makeEntry(
            id: "call-nested",
            kind: .toolCall,
            title: "Ran command",
            body: #"{"command":"npm test","cwd":"/tmp/project"}"#,
            sourceType: "tool-call",
            toolName: "exec_command"
        )
        let stdinEntry = makeEntry(
            id: "stdin-call",
            kind: .toolCall,
            title: "write_stdin",
            body: #"{"chars":"q"}"#,
            sourceType: "tool-call",
            toolName: "write_stdin"
        )
        let stdinResult = makeEntry(
            id: "stdin-result",
            kind: .toolResult,
            title: "write_stdin Result",
            body: "polling",
            sourceType: "tool_result",
            toolName: "write_stdin"
        )

        let coalesced = SessionTranscriptProcessing.coalesceStreamingEntries(in: [
            makePresentation(messageID: "msg-1", sequenceText: "1", createdAt: 100, createdAtText: "10:00", entry: callEntry),
            makePresentation(messageID: "msg-2", sequenceText: "2", createdAt: 101, createdAtText: "10:01", entry: stdinEntry),
            makePresentation(messageID: "msg-3", sequenceText: "3", createdAt: 102, createdAtText: "10:02", entry: stdinResult),
        ])

        guard case .commandExecution(let command)? =
                SessionTranscriptRichContentParser.richToolContent(for: coalesced[0].entries[0]) else {
            Issue.record("Expected command execution card")
            return
        }

        #expect(command.supplementalEntries.map(\.kind) == [.stdin, .toolResult])
        #expect(command.status == .running)
    }

    @Test
    func writeStdinEventsMatchInteractiveCommandBySessionID() {
        let firstCommandCall = SessionTranscriptEntry(
            id: "call-1",
            role: .agent,
            kind: .toolCall,
            title: "Ran command",
            body: #"{"command":"npm test","cwd":"/tmp/project-a"}"#,
            toolUseID: "cmd-a",
            sourceType: "tool-call",
            toolName: "exec_command",
            isSidechain: false,
            threadID: nil
        )
        let firstCommandResult = SessionTranscriptEntry(
            id: "result-1",
            role: .agent,
            kind: .toolResult,
            title: "Ran command Result",
            body: #"{"session_id":"tty-a"}"#,
            toolUseID: "cmd-a",
            sourceType: "tool_result",
            toolName: "exec_command",
            isSidechain: false,
            threadID: nil
        )
        let secondCommandCall = SessionTranscriptEntry(
            id: "call-2",
            role: .agent,
            kind: .toolCall,
            title: "Ran command",
            body: #"{"command":"npm run dev","cwd":"/tmp/project-b"}"#,
            toolUseID: "cmd-b",
            sourceType: "tool-call",
            toolName: "exec_command",
            isSidechain: false,
            threadID: nil
        )
        let secondCommandResult = SessionTranscriptEntry(
            id: "result-2",
            role: .agent,
            kind: .toolResult,
            title: "Ran command Result",
            body: #"{"session_id":"tty-b"}"#,
            toolUseID: "cmd-b",
            sourceType: "tool_result",
            toolName: "exec_command",
            isSidechain: false,
            threadID: nil
        )
        let stdinEntry = SessionTranscriptEntry(
            id: "stdin-call",
            role: .agent,
            kind: .toolCall,
            title: "write_stdin",
            body: #"{"session_id":"tty-b","chars":"q"}"#,
            toolUseID: "stdin-b",
            sourceType: "tool-call",
            toolName: "write_stdin",
            isSidechain: false,
            threadID: nil
        )
        let stdinResult = SessionTranscriptEntry(
            id: "stdin-result",
            role: .agent,
            kind: .toolResult,
            title: "write_stdin Result",
            body: "polling",
            toolUseID: "stdin-b",
            sourceType: "tool_result",
            toolName: "write_stdin",
            isSidechain: false,
            threadID: nil
        )

        let coalesced = SessionTranscriptProcessing.coalesceStreamingEntries(in: [
            makePresentation(messageID: "msg-1", sequenceText: "1", createdAt: 100, createdAtText: "10:00", entry: firstCommandCall),
            makePresentation(messageID: "msg-2", sequenceText: "2", createdAt: 101, createdAtText: "10:01", entry: firstCommandResult),
            makePresentation(messageID: "msg-3", sequenceText: "3", createdAt: 102, createdAtText: "10:02", entry: secondCommandCall),
            makePresentation(messageID: "msg-4", sequenceText: "4", createdAt: 103, createdAtText: "10:03", entry: secondCommandResult),
            makePresentation(messageID: "msg-5", sequenceText: "5", createdAt: 104, createdAtText: "10:04", entry: stdinEntry),
            makePresentation(messageID: "msg-6", sequenceText: "6", createdAt: 105, createdAtText: "10:05", entry: stdinResult),
        ])

        #expect(coalesced.count == 2)

        guard case .commandExecution(let firstCommand)? =
                SessionTranscriptRichContentParser.richToolContent(for: coalesced[0].entries[0]) else {
            Issue.record("Expected first command execution card")
            return
        }
        guard case .commandExecution(let secondCommand)? =
                SessionTranscriptRichContentParser.richToolContent(for: coalesced[1].entries[0]) else {
            Issue.record("Expected second command execution card")
            return
        }

        #expect(firstCommand.command == "npm test")
        #expect(firstCommand.supplementalEntries.map(\.kind) == [.toolResult])
        #expect(firstCommand.status == .running)
        #expect(secondCommand.command == "npm run dev")
        #expect(secondCommand.supplementalEntries.map(\.kind) == [.toolResult, .stdin, .toolResult])
        #expect(secondCommand.status == .running)
    }

    @Test
    func mergesAdjacentExplorationOnlyCommandsIntoSingleCard() {
        let first = makeEntry(
            id: "explore-1",
            kind: .toolResult,
            title: "Ran command",
            body: #"{"command":"cat README.md","cwd":"/tmp/project"}"#,
            sourceType: "item_completed"
        )
        let second = makeEntry(
            id: "explore-2",
            kind: .toolResult,
            title: "Ran command",
            body: #"{"command":"rg TODO Sources","cwd":"/tmp/project"}"#,
            sourceType: "item_completed"
        )

        let coalesced = SessionTranscriptProcessing.coalesceStreamingEntries(in: [
            makePresentation(messageID: "msg-1", sequenceText: "1", createdAt: 100, createdAtText: "10:00", entry: first),
            makePresentation(messageID: "msg-2", sequenceText: "2", createdAt: 101, createdAtText: "10:01", entry: second),
        ])

        #expect(coalesced.count == 1)
        guard case .commandExecution(let command)? =
                SessionTranscriptRichContentParser.richToolContent(for: coalesced[0].entries[0]) else {
            Issue.record("Expected merged exploration card")
            return
        }

        #expect(command.summary == "Explored 1 file, 1 search")
        #expect(command.actions.map(\.kind) == [.read, .search])
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
