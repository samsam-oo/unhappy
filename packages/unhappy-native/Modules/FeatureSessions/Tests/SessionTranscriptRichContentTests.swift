import Foundation
import Testing
@testable import FeatureSessions

struct SessionTranscriptRichContentTests {
    @Test
    func markdownParserBuildsStructuredBlocks() {
        let markdown = """
        # Title

        Intro paragraph with `code`.

        - first item
        - second item

        ```swift
        print("hello")
        ```
        """

        let blocks = SessionTranscriptRichContentParser.markdownBlocks(from: markdown)

        #expect(blocks.count == 4)
        #expect(blocks[0] == .heading(level: 1, text: "Title"))
        #expect(blocks[1] == .paragraph("Intro paragraph with `code`."))
        #expect(blocks[3] == .code(language: "swift", code: "print(\"hello\")"))
    }

    @Test
    func richToolParserBuildsFileChangeCardsFromChangesPayload() {
        let body = """
        {
          "changes": {
            "Sources/App.swift": {
              "type": "update",
              "move_path": null,
              "unified_diff": "@@ -1,1 +1,2 @@\\n-import Foundation\\n+import Foundation\\n+import SwiftUI"
            }
          },
          "auto_approved": false
        }
        """
        let entry = SessionTranscriptEntry(
            id: "tool-1",
            role: .agent,
            kind: .toolCall,
            title: "Edit files",
            body: body,
            toolUseID: "call_1",
            sourceType: "tool-call",
            toolName: "codexpatch",
            isSidechain: false,
            threadID: nil
        )

        let richContent = SessionTranscriptRichContentParser.richToolContent(for: entry)

        guard case .fileChanges(let changes)? = richContent else {
            Issue.record("Expected file changes rich content")
            return
        }

        #expect(changes.count == 1)
        #expect(changes[0].path == "Sources/App.swift")
        #expect(changes[0].kind == .modified)
        #expect(changes[0].diffFiles.count == 1)
        #expect(changes[0].diffFiles[0].hunks.count == 1)
    }

    @Test
    func commandSummaryUsesParsedCommandActions() {
        let body = """
        {
          "commandActions": [
            { "type": "listFiles", "path": "Sources" },
            { "type": "listFiles", "path": "Tests" },
            { "type": "search", "query": "Markdown" }
          ]
        }
        """
        let entry = SessionTranscriptEntry(
            id: "tool-2",
            role: .agent,
            kind: .toolCall,
            title: "Run Command",
            body: body,
            toolUseID: "call_2",
            sourceType: "tool-call",
            toolName: "codexbash",
            isSidechain: false,
            threadID: nil
        )

        let summary = SessionTranscriptRichContentParser.summaryTitle(for: entry)

        #expect(summary == "Listed 2 paths, 1 search")
    }

    @Test
    func commandSummaryUsesExploredForReadFileCounts() {
        let singleReadBody = """
        {
          "commandActions": [
            { "type": "read", "path": "README.md" }
          ]
        }
        """
        let multiReadBody = """
        {
          "commandActions": [
            { "type": "read", "path": "README.md" },
            { "type": "read", "path": "Package.swift" },
            { "type": "search", "query": "TODO" }
          ]
        }
        """

        let singleReadEntry = SessionTranscriptEntry(
            id: "tool-single-read",
            role: .agent,
            kind: .toolCall,
            title: "Run Command",
            body: singleReadBody,
            toolUseID: "call_single",
            sourceType: "tool-call",
            toolName: "codexbash",
            isSidechain: false,
            threadID: nil
        )
        let multiReadEntry = SessionTranscriptEntry(
            id: "tool-multi-read",
            role: .agent,
            kind: .toolCall,
            title: "Run Command",
            body: multiReadBody,
            toolUseID: "call_multi",
            sourceType: "tool-call",
            toolName: "codexbash",
            isSidechain: false,
            threadID: nil
        )

        #expect(SessionTranscriptRichContentParser.summaryTitle(for: singleReadEntry) == "Read 1 file")
        #expect(SessionTranscriptRichContentParser.summaryTitle(for: multiReadEntry) == "Read 2 files, 1 search")
    }

    @Test
    func richToolParserBuildsFileChangeCardsFromLatestItemPayload() {
        let body = """
        {
          "type": "fileChange",
          "id": "item_patch_1",
          "changes": [
            {
              "path": "Sources/ComposerView.swift",
              "kind": {
                "type": "update",
                "move_path": null
              },
              "diff": "@@ -1,1 +1,2 @@\\n-import SwiftUI\\n+import SwiftUI\\n+import CoreKit"
            }
          ]
        }
        """
        let entry = SessionTranscriptEntry(
            id: "tool-3",
            role: .agent,
            kind: .toolCall,
            title: "File Changes",
            body: body,
            toolUseID: "call_3",
            sourceType: "item_started",
            toolName: "codexpatch",
            isSidechain: false,
            threadID: nil
        )

        let richContent = SessionTranscriptRichContentParser.richToolContent(for: entry)

        guard case .fileChanges(let changes)? = richContent else {
            Issue.record("Expected latest file change payload to render as file changes")
            return
        }

        #expect(changes.count == 1)
        #expect(changes[0].path == "Sources/ComposerView.swift")
        #expect(changes[0].kind == .modified)
    }

    @Test
    func richToolParserBuildsCommandExecutionCard() {
        let body = """
        {
          "type": "commandExecutionPresentation",
          "command": "git status",
          "cwd": "/tmp/project",
          "summary": "Explored 2 files, 4 searches",
          "logs": "line 1\\nline 2",
          "success": true,
          "exitCode": 0,
          "durationMs": 11000
        }
        """
        let entry = SessionTranscriptEntry(
            id: "tool-command",
            role: .agent,
            kind: .toolResult,
            title: "Ran command",
            body: body,
            toolUseID: "call_cmd",
            sourceType: "item_completed",
            toolName: "codexbash",
            isSidechain: false,
            threadID: nil
        )

        guard case .commandExecution(let command)? =
                SessionTranscriptRichContentParser.richToolContent(for: entry) else {
            Issue.record("Expected command execution rich content")
            return
        }

        #expect(command.command == "git status")
        #expect(command.cwd == "/tmp/project")
        #expect(command.summary == "Explored 2 files, 4 searches")
        #expect(command.logs == "line 1\nline 2")
        #expect(command.status == .succeeded)
        #expect(command.exitCode == 0)
        #expect(command.durationText == "11s")
    }

    @Test
    func commandStatusPresentationUsesReadableLabelsAndTones() {
        #expect(SessionTranscriptCommandRunPresentation.Status.running.badgeLabel == "Running")
        #expect(SessionTranscriptCommandRunPresentation.Status.running.tone == .running)

        #expect(SessionTranscriptCommandRunPresentation.Status.succeeded.badgeLabel == "Success")
        #expect(SessionTranscriptCommandRunPresentation.Status.succeeded.tone == .success)

        #expect(SessionTranscriptCommandRunPresentation.Status.failed.badgeLabel == "Failed")
        #expect(SessionTranscriptCommandRunPresentation.Status.failed.tone == .failure)
    }

    @Test
    func genericToolParserBuildsSpawnAgentCard() {
        let entry = SessionTranscriptEntry(
            id: "spawn-agent",
            role: .agent,
            kind: .toolResult,
            title: "Spawn Agent Result",
            body: """
            {
              "agent_id": "agent-123",
              "nickname": "Copernicus",
              "agent_type": "worker",
              "message": "Own the transcript rendering path"
            }
            """,
            toolUseID: "tool-spawn",
            sourceType: "tool_result",
            toolName: "spawn_agent",
            isSidechain: false,
            threadID: nil
        )

        guard case .toolDetails(let tool)? =
                SessionTranscriptRichContentParser.richToolContent(for: entry) else {
            Issue.record("Expected generic spawn agent card")
            return
        }

        #expect(tool.kind == .spawnAgent)
        #expect(tool.title == "Spawn Agent")
        #expect(tool.compactSummary == "Copernicus")
        #expect(tool.badgeText == "Started")
        #expect(tool.subtitle == "Own the transcript rendering path")
        #expect(tool.fields.contains(where: { $0.label == "Agent Id" && $0.value == "agent-123" }))
    }

    @Test
    func genericToolParserBuildsWaitCard() {
        let entry = SessionTranscriptEntry(
            id: "wait-agent",
            role: .agent,
            kind: .toolResult,
            title: "Wait Result",
            body: """
            {
              "status": "completed",
              "completed": {
                "message": "Worker finished the patch"
              },
              "timeout_ms": 30000,
              "ids": ["agent-1", "agent-2"]
            }
            """,
            toolUseID: "tool-wait",
            sourceType: "tool_result",
            toolName: "wait",
            isSidechain: false,
            threadID: nil
        )

        guard case .toolDetails(let tool)? =
                SessionTranscriptRichContentParser.richToolContent(for: entry) else {
            Issue.record("Expected generic wait card")
            return
        }

        #expect(tool.kind == .wait)
        #expect(tool.title == "Wait for Agent")
        #expect(tool.compactSummary == "2 agents")
        #expect(tool.badgeText == "Completed")
        #expect(tool.subtitle == "Worker finished the patch")
        #expect(tool.fields.contains(where: { $0.label == "Timeout Ms" && $0.value == "30000 ms" }))
        #expect(tool.fields.contains(where: { $0.label == "Ids" && $0.value == "agent-1, agent-2" }))
    }

    @Test
    func genericToolParserTreatsSendInputAsUserInput() {
        let entry = SessionTranscriptEntry(
            id: "steer-agent",
            role: .agent,
            kind: .toolResult,
            title: "send_input",
            body: """
            {
              "nickname": "Copernicus",
              "text": "Double-check the migration ordering."
            }
            """,
            toolUseID: "tool-steer",
            sourceType: "tool_result",
            toolName: "send_input",
            isSidechain: false,
            threadID: nil
        )

        guard case .toolDetails(let tool)? =
                SessionTranscriptRichContentParser.richToolContent(for: entry) else {
            Issue.record("Expected steer card")
            return
        }

        #expect(tool.kind == .stdin)
        #expect(tool.title == "User Input")
        #expect(tool.compactSummary == "Copernicus")
        #expect(tool.badgeText == "Sent")
        #expect(tool.subtitle == "Double-check the migration ordering.")
        #expect(tool.body == "Double-check the migration ordering.")
    }

    @Test
    func genericToolParserHidesEmptyWriteStdinPoll() {
        let entry = SessionTranscriptEntry(
            id: "stdin-poll",
            role: .agent,
            kind: .toolCall,
            title: "write_stdin",
            body: """
            {
              "session_id": 42046,
              "chars": "",
              "yield_time_ms": 1000
            }
            """,
            toolUseID: "tool-poll",
            sourceType: "tool_call",
            toolName: "write_stdin",
            isSidechain: false,
            threadID: nil
        )

        #expect(SessionTranscriptRichContentParser.richToolContent(for: entry) == nil)
    }

    @Test
    func diffSummaryReadsAsEditedFiles() {
        let entry = SessionTranscriptEntry(
            id: "diff-summary",
            role: .agent,
            kind: .toolResult,
            title: "Tool Result",
            body: """
            diff --git a/Sources/App.swift b/Sources/App.swift
            @@ -1,1 +1,2 @@
            -import Foundation
            +import Foundation
            +import SwiftUI
            """,
            toolUseID: "tool-diff",
            sourceType: "tool_result",
            toolName: "diff",
            isSidechain: false,
            threadID: nil
        )

        #expect(SessionTranscriptRichContentParser.summaryTitle(for: entry) == "Edited App.swift")
        #expect(SessionTranscriptRichContentParser.summarySubtitle(for: entry) == "1 hunk")
    }

    @Test
    func markdownParserTreatsStandaloneImageAsImageBlock() {
        let blocks = SessionTranscriptRichContentParser.markdownBlocks(
            from: "![Screenshot](/tmp/screenshot.png)"
        )

        #expect(blocks.count == 1)
        guard case .image(let altText, let source) = blocks[0] else {
            Issue.record("Expected image block")
            return
        }
        #expect(altText == "Screenshot")
        #expect(source == "/tmp/screenshot.png")
    }

    @Test
    func attributedInlineMarkdownNormalizesSkillLinksToReadableMentions() {
        let attributed = SessionTranscriptRichContentParser.attributedInlineMarkdown(
            "Use [$openai-docs](/Users/test/.codex/skills/openai-docs/SKILL.md) for the API docs."
        )
        let plainText = attributed.map { String($0.characters) } ?? ""

        #expect(attributed != nil)
        #expect(plainText.contains("$openai-docs"))
        #expect(plainText.contains("SKILL.md") == false)
    }
}
