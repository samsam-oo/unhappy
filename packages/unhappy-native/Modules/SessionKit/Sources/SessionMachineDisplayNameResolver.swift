import Foundation

public enum SessionMachineDisplayNameResolver {
    public static func resolve(in objects: [[String: Any]]) -> String? {
        if let primary = bestDisplayString(
            in: objects,
            keys: ["displayName", "name", "machineName", "deviceName", "computerName"],
            rejectGenericHosts: true,
            rejectOpaqueIdentifiers: true
        ) {
            return primary
        }
        return bestDisplayString(
            in: objects,
            keys: ["host", "hostname", "computerName", "localHostName", "hostName", "machineHost"],
            rejectGenericHosts: true,
            rejectOpaqueIdentifiers: true
        )
    }

    public static func preferred(
        existing: String,
        candidate: String?,
        machineID: String
    ) -> String {
        let trimmedExisting = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let candidate else {
            return trimmedExisting.isEmpty ? machineID : trimmedExisting
        }

        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCandidate.isEmpty else {
            return trimmedExisting.isEmpty ? machineID : trimmedExisting
        }

        let candidateIsReadable = isReadableDisplayName(trimmedCandidate, machineID: machineID)
        let existingIsReadable = isReadableDisplayName(trimmedExisting, machineID: machineID)

        if candidateIsReadable && !existingIsReadable {
            return trimmedCandidate
        }
        if trimmedExisting.isEmpty {
            return trimmedCandidate
        }
        return trimmedExisting
    }

    private static func isReadableDisplayName(_ value: String, machineID: String) -> Bool {
        guard let normalized = normalizeDisplayValue(
            value,
            rejectGenericHosts: true,
            rejectOpaqueIdentifiers: true
        ) else {
            return false
        }
        return normalized.caseInsensitiveCompare(machineID) != .orderedSame
    }

    private static func bestDisplayString(
        in objects: [[String: Any]],
        keys: [String],
        rejectGenericHosts: Bool,
        rejectOpaqueIdentifiers: Bool
    ) -> String? {
        let normalizedKeys = Set(keys.map(normalizeKey))
        for object in objects {
            let candidates = values(in: object, matching: normalizedKeys)
            for candidate in candidates {
                if let normalized = normalizeDisplayValue(
                    candidate,
                    rejectGenericHosts: rejectGenericHosts,
                    rejectOpaqueIdentifiers: rejectOpaqueIdentifiers
                ) {
                    return normalized
                }
            }
        }
        return nil
    }

    private static func normalizeDisplayValue(
        _ raw: String,
        rejectGenericHosts: Bool,
        rejectOpaqueIdentifiers: Bool
    ) -> String? {
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

    private static func looksLikeOpaqueIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func values(in object: Any?, matching keys: Set<String>) -> [String] {
        var output: [String] = []
        collectValues(in: object, matching: keys, output: &output)
        return output
    }

    private static func collectValues(
        in object: Any?,
        matching keys: Set<String>,
        output: inout [String]
    ) {
        if let dictionary = object as? [String: Any] {
            for (rawKey, value) in dictionary where keys.contains(normalizeKey(rawKey)) {
                if let string = value as? String {
                    output.append(string)
                } else if let number = value as? NSNumber {
                    output.append(number.stringValue)
                }
            }
            for (_, value) in dictionary {
                collectValues(in: value, matching: keys, output: &output)
            }
            return
        }

        if let array = object as? [Any] {
            for item in array {
                collectValues(in: item, matching: keys, output: &output)
            }
        }
    }

    private static func normalizeKey(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
