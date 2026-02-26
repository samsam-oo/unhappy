import Foundation
import CoreKit

struct SessionInfoPayloadField: Equatable, Identifiable, Sendable {
    let key: String
    let value: String

    var id: String { key }
}

struct SessionInfoPresentation: Equatable, Sendable {
    let sessionID: String
    let title: String?
    let active: Bool
    let sequenceText: String?
    let createdAtText: String
    let activeAtText: String
    let updatedAtText: String
    let metadataVersionText: String
    let agentStateVersionText: String?
    let dataEncryptionKeyPreview: String?
    let metadataCharacterCount: Int
    let metadataPreview: String
    let metadataTruncated: Bool
    let metadataFields: [SessionInfoPayloadField]
    let agentStateCharacterCount: Int
    let agentStatePreview: String?
    let agentStateTruncated: Bool
    let agentStateFields: [SessionInfoPayloadField]
}

enum SessionInfoPresentationBuilder {
    static let metadataPreviewLimit = 2_000
    static let fieldValueLimit = 400

    static func make(
        from session: APISession,
        timestampFormatter: (TimeInterval) -> String = defaultTimestampFormatter
    ) -> SessionInfoPresentation {
        let metadataPreview = truncate(session.metadata, limit: metadataPreviewLimit)
        let agentStateRaw = normalizedOptional(session.agentState)
        let agentStatePreview = agentStateRaw.map { truncate($0, limit: metadataPreviewLimit) }
        let metadataFields = parseJSONFields(raw: session.metadata)
        let agentStateFields = parseJSONFields(raw: agentStateRaw ?? "")

        return SessionInfoPresentation(
            sessionID: session.id,
            title: normalizedOptional(session.displayName),
            active: session.active,
            sequenceText: session.seq.map { "#\($0)" },
            createdAtText: timestampFormatter(session.createdAt),
            activeAtText: timestampFormatter(session.activeAt),
            updatedAtText: timestampFormatter(session.updatedAt),
            metadataVersionText: "\(session.metadataVersion)",
            agentStateVersionText: session.agentStateVersion.map(String.init),
            dataEncryptionKeyPreview: session.dataEncryptionKey.map(maskSensitiveValue),
            metadataCharacterCount: session.metadata.count,
            metadataPreview: metadataPreview.value,
            metadataTruncated: metadataPreview.truncated,
            metadataFields: metadataFields,
            agentStateCharacterCount: agentStateRaw?.count ?? 0,
            agentStatePreview: agentStatePreview?.value,
            agentStateTruncated: agentStatePreview?.truncated ?? false,
            agentStateFields: agentStateFields
        )
    }

    private static func defaultTimestampFormatter(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .medium)
    }

    private static func normalizedOptional(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func truncate(_ value: String, limit: Int) -> (value: String, truncated: Bool) {
        guard value.count > limit else { return (value, false) }
        return (String(value.prefix(limit)), true)
    }

    private static func parseJSONFields(raw: String) -> [SessionInfoPayloadField] {
        guard !raw.isEmpty else { return [] }
        guard let data = raw.data(using: .utf8) else { return [] }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        guard let dictionary = object as? [String: Any] else { return [] }

        return dictionary.keys.sorted().map { key in
            SessionInfoPayloadField(
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
            return truncate(string, limit: fieldValueLimit).value
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let string = String(data: data, encoding: .utf8) {
            return truncate(string, limit: fieldValueLimit).value
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        return truncate(String(describing: value), limit: fieldValueLimit).value
    }

    private static func maskSensitiveValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "present" }
        if trimmed.count <= 10 {
            return "••••••••"
        }
        let prefix = trimmed.prefix(4)
        let suffix = trimmed.suffix(4)
        return "\(prefix)…\(suffix)"
    }
}
