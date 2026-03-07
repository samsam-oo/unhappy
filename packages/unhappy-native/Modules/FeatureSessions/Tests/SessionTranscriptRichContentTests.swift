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

        #expect(summary == "Explored 2 paths, 1 search")
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

        #expect(SessionTranscriptRichContentParser.summaryTitle(for: singleReadEntry) == "Explored 1 file")
        #expect(SessionTranscriptRichContentParser.summaryTitle(for: multiReadEntry) == "Explored 2 files, 1 search")
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
}
