import Foundation

struct SessionQueuedComposerDraft: Identifiable, Equatable, Sendable {
    let id: String
    let text: String
    let attachments: [SessionComposerImageAttachment]
    let createdAt: TimeInterval

    init(
        id: String = UUID().uuidString.lowercased(),
        text: String,
        attachments: [SessionComposerImageAttachment],
        createdAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.text = text
        self.attachments = attachments
        self.createdAt = createdAt
    }

    var previewText: String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if attachments.isEmpty {
            return normalized
        }
        if normalized.isEmpty {
            return "[\(attachments.count) image\(attachments.count == 1 ? "" : "s")]"
        }
        return "\(normalized) [+\(attachments.count) image\(attachments.count == 1 ? "" : "s")]"
    }
}
