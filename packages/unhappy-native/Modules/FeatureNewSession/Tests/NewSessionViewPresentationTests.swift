import Testing
import CoreKit
@testable import FeatureNewSession

struct NewSessionViewPresentationTests {
    @Test
    func projectScopedStartSessionHidesProjectRedundantSections() {
        #expect(
            NewSessionViewPresentation.isProjectScopedStartSession(
                mode: .startSession,
                initialDirectoryPath: "/repo/app"
            )
        )
        #expect(
            !NewSessionViewPresentation.isProjectScopedStartSession(
                mode: .selectProject,
                initialDirectoryPath: "/repo/app"
            )
        )
    }

    @Test
    func existingSessionSelectionTracksCurrentAgentOnly() {
        #expect(
            NewSessionViewPresentation.activeResumeSelectionID(
                selectedAgent: .codex,
                codexResumeThreadID: "codex-thread",
                claudeResumeSessionID: "claude-session"
            ) == "codex-thread"
        )
        #expect(
            NewSessionViewPresentation.activeResumeSelectionID(
                selectedAgent: .claude,
                codexResumeThreadID: "codex-thread",
                claudeResumeSessionID: "claude-session"
            ) == "claude-session"
        )
        #expect(
            NewSessionViewPresentation.activeResumeSelectionID(
                selectedAgent: .gemini,
                codexResumeThreadID: "codex-thread",
                claudeResumeSessionID: "claude-session"
            ) == nil
        )
    }

    @Test
    func existingSessionPickerButtonUsesUnifiedTitle() {
        #expect(
            NewSessionViewPresentation.existingSessionButtonTitle(
                selectedAgent: .codex,
                codexResumeThreadID: "",
                claudeResumeSessionID: ""
            ) == "Choose Existing Session"
        )
        #expect(
            NewSessionViewPresentation.existingSessionButtonTitle(
                selectedAgent: .claude,
                codexResumeThreadID: "",
                claudeResumeSessionID: "claude-session-123456"
            )?.contains("Existing Session:") == true
        )
        #expect(
            NewSessionViewPresentation.existingSessionButtonTitle(
                selectedAgent: .gemini,
                codexResumeThreadID: "codex-thread",
                claudeResumeSessionID: "claude-session"
            ) == nil
        )
    }
}
