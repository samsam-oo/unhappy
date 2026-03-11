import Foundation
import CoreKit
import SessionKit

struct SessionMessagePayloadField: Equatable, Identifiable, Sendable {
    let key: String
    let value: String

    var id: String { key }
}

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
    let payloadFields: [SessionMessagePayloadField]
    let parsedEntries: [SessionTranscriptEntry]
}

enum SessionMessageDetailPresentationBuilder {
    static let payloadPreviewLimit = 4_000
    static let payloadFieldValueLimit = 600

    static func make(
        from message: APISessionMessage,
        transcriptPresentation: SessionTranscriptMessagePresentation? = nil,
        timestampFormatter: (TimeInterval) -> String = defaultTimestampFormatter
    ) -> SessionMessageDetailPresentation {
        let normalizedContentType = message.content?.type.trimmingCharacters(in: .whitespacesAndNewlines)
        let contentType = normalizedContentType?.isEmpty == false ? normalizedContentType : nil
        let payload = message.content?.payload
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
        let payloadFields = parsePayloadFields(payload)
        let parsedEntries = {
            if let transcriptPresentation {
                return transcriptPresentation.entries
            }
            return SessionTranscriptPresentationBuilder.parseEntries(
                payloadString: payload,
                messageID: message.id
            )
        }()

        return SessionMessageDetailPresentation(
            id: message.id,
            sequenceText: "\(message.seq)",
            localID: message.localId,
            createdAtText: timestampFormatter(message.createdAt),
            updatedAtText: timestampFormatter(message.updatedAt),
            contentType: contentType,
            payloadPreview: payloadPreview,
            payloadCharacterCount: payloadCharacterCount,
            payloadTruncated: payloadTruncated,
            payloadFields: payloadFields,
            parsedEntries: parsedEntries
        )
    }

    private static func defaultTimestampFormatter(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .medium)
    }

    private static func parsePayloadFields(_ payload: String?) -> [SessionMessagePayloadField] {
        guard let payload, !payload.isEmpty else { return [] }
        guard let data = payload.data(using: .utf8) else { return [] }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        guard let dictionary = object as? [String: Any] else { return [] }

        return dictionary.keys.sorted().map { key in
            SessionMessagePayloadField(
                key: key,
                value: stringify(dictionary[key])
            )
        }
    }

    private static func stringify(_ value: Any?) -> String {
        guard let value else { return "" }
        if value is NSNull {
            return "null"
        }
        if let string = value as? String {
            return truncate(string)
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let string = String(data: data, encoding: .utf8) {
            return truncate(string)
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        return truncate(String(describing: value))
    }

    private static func truncate(_ value: String) -> String {
        if value.count <= payloadFieldValueLimit {
            return value
        }
        return String(value.prefix(payloadFieldValueLimit)) + "…"
    }
}
