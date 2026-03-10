import Foundation
import Testing
@testable import FeatureSessions

struct SessionTranscriptLogLineDisplayModeTests {
    @Test
    func commandExecutionEntriesUseCollapsibleReferenceMode() {
        let entry = SessionTranscriptEntry(
            id: "command",
            role: .agent,
            kind: .toolResult,
            title: "Ran command",
            body: #"{"type":"commandExecutionPresentation","command":"git status","logs":"ok","success":true}"#,
            toolUseID: "tool-1",
            sourceType: "tool_result",
            toolName: "exec_command",
            isSidechain: false,
            threadID: nil
        )

        let mode = SessionTranscriptLogLineDisplayMode.resolve(for: entry)

        #expect(mode == .collapsibleReference)
    }

    @Test
    func userTextEntriesStayInMainMessageMode() {
        let entry = SessionTranscriptEntry(
            id: "text",
            role: .user,
            kind: .text,
            title: nil,
            body: "hello",
            toolUseID: nil,
            sourceType: "text",
            toolName: nil,
            isSidechain: false,
            threadID: nil
        )

        let mode = SessionTranscriptLogLineDisplayMode.resolve(for: entry)

        #expect(mode == .mainMessage)
    }
}
