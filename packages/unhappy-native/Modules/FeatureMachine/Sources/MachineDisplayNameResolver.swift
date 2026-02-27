import Foundation
import CoreKit

enum MachineDisplayNameResolver {
    static func displayName(for machine: APIMachine) -> String {
        guard let metadata = parseJSONObject(raw: machine.metadata) else {
            return machine.id
        }

        if let host = firstString(in: metadata, keys: ["host", "hostname", "computerName"]) {
            return host
        }
        if let name = firstString(in: metadata, keys: ["displayName", "name", "machineName"]) {
            return name
        }
        return machine.id
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
