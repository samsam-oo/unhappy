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
    let machineDisplayName: String?
    let machineIdentifier: String?
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
        let metadataObject = parseJSONObject(raw: session.metadata)
        let metadataFields = parseJSONFields(object: metadataObject)
        let agentStateFields = parseJSONFields(object: parseJSONObject(raw: agentStateRaw ?? ""))

        return SessionInfoPresentation(
            sessionID: session.id,
            title: normalizedOptional(session.displayName),
            machineDisplayName: machineDisplayName(from: metadataObject),
            machineIdentifier: firstString(in: metadataObject, keys: [
                "machineId", "machineID", "machine_id",
            ]),
            active: session.active,
            sequenceText: session.seq.map(String.init),
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

    private static func parseJSONFields(object: [String: Any]?) -> [SessionInfoPayloadField] {
        guard let dictionary = object else { return [] }

        return dictionary.keys.sorted().map { key in
            SessionInfoPayloadField(
                key: key,
                value: stringify(dictionary[key])
            )
        }
    }

    private static func parseJSONObject(raw: String) -> [String: Any]? {
        let payload = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return nil }

        if let data = payload.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let dictionary = object as? [String: Any] {
            return dictionary
        }

        if let decoded = decodeBase64(payload),
           let object = try? JSONSerialization.jsonObject(with: decoded),
           let dictionary = object as? [String: Any] {
            return dictionary
        }

        return nil
    }

    private static func machineDisplayName(from metadata: [String: Any]?) -> String? {
        if let host = firstString(in: metadata, keys: ["host", "hostname", "computerName"]) {
            return host
        }
        return firstString(in: metadata, keys: ["displayName", "name", "machineName"])
    }

    private static func firstString(in object: Any?, keys: [String]) -> String? {
        let normalizedKeys = Set(keys.map(normalizeKey))
        guard let value = firstValue(in: object, matching: normalizedKeys) else {
            return nil
        }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func firstValue(in object: Any?, matching keys: Set<String>) -> Any? {
        if let dictionary = object as? [String: Any] {
            for (rawKey, value) in dictionary {
                if keys.contains(normalizeKey(rawKey)) {
                    return value
                }
            }
            for (_, value) in dictionary {
                if let nested = firstValue(in: value, matching: keys) {
                    return nested
                }
            }
            return nil
        }

        if let array = object as? [Any] {
            for item in array {
                if let nested = firstValue(in: item, matching: keys) {
                    return nested
                }
            }
        }
        return nil
    }

    private static func normalizeKey(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
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

    private static func decodeBase64(_ raw: String) -> Data? {
        if let direct = Data(base64Encoded: raw) {
            return direct
        }
        let replaced = raw
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingCount = (4 - (replaced.count % 4)) % 4
        let padded = replaced + String(repeating: "=", count: paddingCount)
        return Data(base64Encoded: padded)
    }
}
