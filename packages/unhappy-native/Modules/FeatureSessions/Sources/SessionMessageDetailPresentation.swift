import Foundation
import CoreKit

struct SessionMessageDetailPresentation: Equatable, Sendable {
    let id: String
    let sequenceText: String
    let localID: String?
    let createdAtText: String
    let updatedAtText: String
    let contentType: String?
    let payloadPreview: String?
    let payloadCharacterCount: Int
    let payloadTruncated: Bool
}

enum SessionMessageDetailPresentationBuilder {
    static let payloadPreviewLimit = 4_000

    static func make(
        from message: APISessionMessage,
        timestampFormatter: (TimeInterval) -> String = defaultTimestampFormatter
    ) -> SessionMessageDetailPresentation {
        let normalizedContentType = message.content?.t.trimmingCharacters(in: .whitespacesAndNewlines)
        let contentType = normalizedContentType?.isEmpty == false ? normalizedContentType : nil
        let payload = message.content?.c
        let payloadCharacterCount = payload?.count ?? 0

        let payloadPreview: String?
        let payloadTruncated: Bool
        if let payload, payload.count > payloadPreviewLimit {
            payloadPreview = String(payload.prefix(payloadPreviewLimit))
            payloadTruncated = true
        } else {
            payloadPreview = payload
            payloadTruncated = false
        }

        return SessionMessageDetailPresentation(
            id: message.id,
            sequenceText: "#\(message.seq)",
            localID: message.localId,
            createdAtText: timestampFormatter(message.createdAt),
            updatedAtText: timestampFormatter(message.updatedAt),
            contentType: contentType,
            payloadPreview: payloadPreview,
            payloadCharacterCount: payloadCharacterCount,
            payloadTruncated: payloadTruncated
        )
    }

    private static func defaultTimestampFormatter(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .medium)
    }
}
