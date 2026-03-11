import Foundation

public enum DirectSessionTranscriptAutoPagingDecision {
    public static func shouldTrigger(
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

    public static func shouldRestoreOlderAnchor(
        pendingAnchorMessageID: String?,
        currentFirstMessageID: String?
    ) -> Bool {
        guard let pendingAnchorMessageID else { return false }
        guard !pendingAnchorMessageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard let currentFirstMessageID else { return false }
        return currentFirstMessageID != pendingAnchorMessageID
    }
}
