import Foundation

enum DirectSessionTranscriptAutoPagingDecision {
    static func shouldTrigger(
        currentTriggerID: String?,
        lastTriggeredID: String?,
        isTopPagingRowVisible: Bool,
        isNearTranscriptBottom: Bool,
        isLoadingOlderMessages: Bool
    ) -> Bool {
        guard isTopPagingRowVisible else { return false }
        guard isNearTranscriptBottom == false else { return false }
        guard isLoadingOlderMessages == false else { return false }
        guard let currentTriggerID else { return false }
        let trimmed = currentTriggerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed != lastTriggeredID
    }
}
