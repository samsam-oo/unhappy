import Foundation

enum DirectSessionPollingStrategy {
    static let incrementalRefreshPageSize = 20

    static func shouldRefreshLatestMessages(
        hasExistingMessages: Bool,
        isSending: Bool,
        isLoadingOlderMessages: Bool,
        hasPendingPostSendRefresh: Bool,
        hasActiveMessagesLoad: Bool
    ) -> Bool {
        if hasExistingMessages == false {
            return hasActiveMessagesLoad == false
        }
        if isSending || isLoadingOlderMessages || hasPendingPostSendRefresh {
            return false
        }
        return hasActiveMessagesLoad == false
    }

    static func refreshLimit(
        hasExistingMessages: Bool,
        defaultPageSize: Int
    ) -> Int {
        hasExistingMessages
            ? min(incrementalRefreshPageSize, defaultPageSize)
            : defaultPageSize
    }
}
