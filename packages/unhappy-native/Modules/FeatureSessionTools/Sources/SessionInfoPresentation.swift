import Foundation
import CoreKit

struct SessionInfoPayloadField: Equatable, Identifiable, Sendable {
    let key: String
    let value: String

    var id: String { key }
}

struct SessionInfoPresentation: Equatable, Sendable {
    let sessionID: String
    let title: String
    let isFallbackTitle: Bool
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
        let agentStateObject = parseJSONObject(raw: agentStateRaw ?? "")
        let metadataFields = parseJSONFields(object: metadataObject)
        let agentStateFields = parseJSONFields(object: agentStateObject)
        let resolvedTitle = sessionTitle(
            for: session,
            metadata: metadataObject,
            agentState: agentStateObject
        )

        return SessionInfoPresentation(
            sessionID: session.id,
            title: resolvedTitle.value,
            isFallbackTitle: resolvedTitle.isFallback,
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
        if let name = bestDisplayString(
            in: metadata,
            keys: ["displayName", "name", "machineName", "deviceName", "computerName"],
            rejectGenericHosts: true,
            rejectOpaqueIdentifiers: true
        ) {
            return name
        }
        if let host = bestDisplayString(
            in: metadata,
            keys: ["host", "hostname", "computerName", "localHostName", "hostName", "machineHost"],
            rejectGenericHosts: true,
            rejectOpaqueIdentifiers: true
        ) {
            return host
        }
        return nil
    }

    private static func sessionTitle(
        for session: APISession,
        metadata: [String: Any]?,
        agentState: [String: Any]?
    ) -> (value: String, isFallback: Bool) {
        if let displayName = normalizedOptional(session.displayName),
           displayName != session.id {
            return (displayName, false)
        }

        if let summary = summaryText(in: [agentState, metadata]) {
            return (summary, false)
        }

        if let metadataName = firstString(
            in: [agentState, metadata],
            keys: ["displayName", "name", "title", "threadName", "sessionName"]
        ),
           metadataName != session.id {
            return (metadataName, false)
        }

        if let seq = session.seq, seq > 0 {
            return ("Session \(seq)", true)
        }

        return ("Session", true)
    }

    private static func summaryText(in objects: [Any?]) -> String? {
        for object in objects {
            guard let object else { continue }
            if let dictionary = object as? [String: Any] {
                if let summaryObject = dictionary["summary"] as? [String: Any],
                   let text = normalizedOptional(summaryObject["text"] as? String) {
                    return text
                }
                if let summary = normalizedOptional(dictionary["summary"] as? String) {
                    return summary
                }
                if let nested = summaryText(in: Array(dictionary.values)) {
                    return nested
                }
            } else if let array = object as? [Any] {
                if let nested = summaryText(in: array) {
                    return nested
                }
            }
        }
        return nil
    }

    private static func bestDisplayString(
        in object: Any?,
        keys: [String],
        rejectGenericHosts: Bool,
        rejectOpaqueIdentifiers: Bool
    ) -> String? {
        let normalizedKeys = Set(keys.map(normalizeKey))
        guard let value = firstValue(in: object, matching: normalizedKeys) else {
            return nil
        }
        return normalizeDisplayValue(
            value,
            rejectGenericHosts: rejectGenericHosts,
            rejectOpaqueIdentifiers: rejectOpaqueIdentifiers
        )
    }

    private static func normalizeDisplayValue(
        _ value: Any,
        rejectGenericHosts: Bool,
        rejectOpaqueIdentifiers: Bool
    ) -> String? {
        let raw: String
        if let string = value as? String {
            raw = string
        } else if let number = value as? NSNumber {
            raw = number.stringValue
        } else {
            return nil
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withoutLocalSuffix = trimmed.replacingOccurrences(
            of: #"\.local$"#,
            with: "",
            options: .regularExpression
        )
        let lowered = withoutLocalSuffix.lowercased()
        let blockedValues: Set<String> = [
            "mac",
            "localhost",
            "unknown-host",
        ]
        if rejectGenericHosts && blockedValues.contains(lowered) {
            return nil
        }
        if rejectOpaqueIdentifiers && looksLikeOpaqueIdentifier(withoutLocalSuffix) {
            return nil
        }
        return withoutLocalSuffix
    }

    private static func looksLikeOpaqueIdentifier(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.range(
            of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        if trimmed.range(of: #"^[0-9a-fA-F]{20,}$"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"^[0-9]{10,}$"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"^[a-z0-9-]{24,}$"#, options: .regularExpression) != nil,
           trimmed.lowercased().contains("macbook") == false {
            return true
        }
        return false
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
