import CoreKit

enum NewSessionViewPresentation {
    static func isProjectScopedStartSession(
        mode: NewSessionView.Mode,
        initialDirectoryPath: String?
    ) -> Bool {
        guard mode == .startSession else { return false }
        guard let initialDirectoryPath else { return false }
        return !initialDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func activeResumeSelectionID(
        selectedAgent: APISessionSpawnAgent,
        codexResumeThreadID: String,
        claudeResumeSessionID: String
    ) -> String? {
        switch selectedAgent {
        case .codex:
            return normalizedOptional(codexResumeThreadID)
        case .claude:
            return normalizedOptional(claudeResumeSessionID)
        case .gemini:
            return nil
        }
    }

    static func showsExistingSessionPicker(
        selectedAgent: APISessionSpawnAgent
    ) -> Bool {
        selectedAgent == .codex || selectedAgent == .claude
    }

    static func existingSessionButtonTitle(
        selectedAgent: APISessionSpawnAgent,
        codexResumeThreadID: String,
        claudeResumeSessionID: String
    ) -> String? {
        guard showsExistingSessionPicker(selectedAgent: selectedAgent) else { return nil }
        if let selectionID = activeResumeSelectionID(
            selectedAgent: selectedAgent,
            codexResumeThreadID: codexResumeThreadID,
            claudeResumeSessionID: claudeResumeSessionID
        ) {
            return "Existing Session: \(abbreviatedIdentifier(selectionID))"
        }
        return "Choose Existing Session"
    }

    static func existingSessionErrorMessage(
        selectedAgent: APISessionSpawnAgent,
        codexErrorMessage: String?,
        claudeErrorMessage: String?
    ) -> String? {
        switch selectedAgent {
        case .codex:
            return normalizedOptional(codexErrorMessage)
        case .claude:
            return normalizedOptional(claudeErrorMessage)
        case .gemini:
            return nil
        }
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func abbreviatedIdentifier(_ value: String) -> String {
        guard value.count > 16 else { return value }
        let prefix = value.prefix(8)
        let suffix = value.suffix(6)
        return "\(prefix)…\(suffix)"
    }
}
