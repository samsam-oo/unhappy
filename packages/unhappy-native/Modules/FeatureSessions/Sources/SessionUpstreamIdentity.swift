import Foundation
import CoreKit

struct SessionUpstreamIdentity: Equatable, Sendable {
    let machineID: String
    let provider: APIUpstreamSessionProvider
    let upstreamSessionID: String
    let workingDirectory: String?
    let machineDisplayName: String?

    var key: String {
        "\(machineID)|\(provider.rawValue)|\(upstreamSessionID)"
    }

    init?(
        session: APISession
    ) {
        let metadata = SessionPayloadValueResolver.decodeJSONObject(
            payload: session.metadata,
            dataEncryptionKey: session.dataEncryptionKey
        )
        let agentState = SessionPayloadValueResolver.decodeJSONObject(
            payload: session.agentState,
            dataEncryptionKey: session.dataEncryptionKey
        )

        guard let provider = Self.resolveProvider(in: [agentState, metadata]) else {
            return nil
        }
        guard let machineID = Self.resolveRequiredString(
            in: [agentState, metadata],
            keys: ["machineId", "machine_id"]
        ) else {
            return nil
        }
        guard let upstreamSessionID = Self.resolveRequiredString(
            in: [agentState, metadata],
            keys: [
                "agentSessionId",
                "agent_session_id",
                "upstreamSessionId",
                "upstream_session_id",
            ]
        ) else {
            return nil
        }

        self.machineID = machineID
        self.provider = provider
        self.upstreamSessionID = upstreamSessionID
        self.workingDirectory = Self.resolveOptionalString(
            in: [agentState, metadata],
            keys: [
                "cwd",
                "path",
                "directory",
                "workingDirectory",
                "workDir",
                "projectPath",
            ]
        )
        self.machineDisplayName = Self.resolveMachineDisplayName(in: [metadata, agentState])
    }

    private static func resolveProvider(in objects: [[String: Any]]) -> APIUpstreamSessionProvider? {
        guard let raw = resolveOptionalString(
            in: objects,
            keys: ["flavor", "agent", "provider"]
        ) else {
            return nil
        }
        let normalized = raw.lowercased()
        if let exact = APIUpstreamSessionProvider(rawValue: normalized) {
            return exact
        }
        if normalized.contains("claude") {
            return .claude
        }
        if normalized.contains("gemini") {
            return .gemini
        }
        if normalized.contains("codex") || normalized.contains("openai") || normalized.contains("gpt") {
            return .codex
        }
        return nil
    }

    private static func resolveRequiredString(in objects: [[String: Any]], keys: [String]) -> String? {
        resolveOptionalString(in: objects, keys: keys)
    }

    private static func resolveOptionalString(in objects: [[String: Any]], keys: [String]) -> String? {
        SessionPayloadValueResolver.firstString(in: objects, keys: keys)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
    }

    private static func resolveMachineDisplayName(in objects: [[String: Any]]) -> String? {
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

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
