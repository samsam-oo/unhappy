import Foundation
import CoreKit

public struct SessionMessagePayloadField: Equatable, Identifiable, Sendable {
    public let key: String
    public let value: String

    public var id: String { key }
}

public struct SessionMessageDetailPresentation: Equatable, Sendable {
    public let id: String
    public let sequenceText: String
    public let localID: String?
    public let createdAtText: String
    public let updatedAtText: String
    public let contentType: String?
    public let payloadPreview: String?
    public let payloadCharacterCount: Int
    public let payloadTruncated: Bool
    public let payloadFields: [SessionMessagePayloadField]
    public let parsedEntries: [SessionTranscriptEntry]
}

public enum SessionMessageDetailPresentationBuilder {
    public static let payloadPreviewLimit = 4_000
    public static let payloadFieldValueLimit = 600

    public static func make(
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

    public static func defaultTimestampFormatter(_ timestamp: TimeInterval) -> String {
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
