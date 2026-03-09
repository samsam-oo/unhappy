import Foundation
import CryptoKit
import CoreKit
import SecurityKit

enum MachineDisplayNameResolver {
    private static let payloadBundleVersion: UInt8 = 2
    private static let aesGCMNonceLength = 12
    private static let aesGCMTagLength = 16
    private static let minimumPayloadBundleLength = 1 + aesGCMNonceLength + aesGCMTagLength

    static func displayName(for machine: APIMachine) -> String {
        guard let metadata = parseJSONObject(
            raw: machine.metadata,
            dataEncryptionKey: machine.dataEncryptionKey,
            machineID: machine.id
        ) else {
            return fallbackDisplayName(for: machine)
        }

        let primaryNameKeys = [
            "displayName", "name", "machineName", "deviceName", "computerName",
        ]
        let hostKeys = [
            "host", "hostname", "computerName", "localHostName", "hostName", "machineHost",
        ]

        if let name = bestDisplayString(
            in: metadata,
            keys: primaryNameKeys,
            rejectGenericHosts: true,
            rejectOpaqueIdentifiers: true
        ) {
            return name
        }
        if let host = bestDisplayString(
            in: metadata,
            keys: hostKeys,
            rejectGenericHosts: true,
            rejectOpaqueIdentifiers: true
        ) {
            return host
        }

        return fallbackDisplayName(for: machine)
    }

    private static func parseJSONObject(
        raw: String,
        dataEncryptionKey: String?,
        machineID: String
    ) -> [String: Any]? {
        let payload = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return nil }

        if let data = payload.data(using: .utf8),
           let dictionary = parseJSONObject(fromData: data) {
            return dictionary
        }

        if let decoded = decodeBase64(payload),
           let dictionary = parseJSONObject(fromData: decoded) {
            return dictionary
        }

        if let decrypted = decryptDataKeyPayload(
            payload: payload,
            dataEncryptionKey: dataEncryptionKey,
            machineID: machineID
        ),
           let dictionary = parseJSONObject(fromData: decrypted) {
            return dictionary
        }

        return nil
    }

    private static func parseJSONObject(fromData data: Data) -> [String: Any]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        if let dictionary = object as? [String: Any] {
            return dictionary
        }
        if let encoded = object as? String,
           let nestedData = encoded.data(using: .utf8),
           let nested = try? JSONSerialization.jsonObject(with: nestedData) as? [String: Any] {
            return nested
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

    private static func fallbackDisplayName(for machine: APIMachine) -> String {
        if let seq = machine.seq, seq > 0 {
            return "Machine \(seq)"
        }
        return "Machine"
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
            for (rawKey, value) in dictionary {
                if keys.contains(normalizeKey(rawKey)) {
                    if let string = value as? String {
                        output.append(string)
                    } else if let number = value as? NSNumber {
                        output.append(number.stringValue)
                    }
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

    private static func decryptDataKeyPayload(
        payload: String,
        dataEncryptionKey: String?,
        machineID: String
    ) -> Data? {
        guard let keyData = MachineDataPlaneEncryption.resolveMachineDataKey(
            rawWrappedKey: dataEncryptionKey,
            machineID: machineID
        ), keyData.count == 32 else {
            return nil
        }
        guard let bundle = decodeBase64(payload) else {
            return nil
        }
        guard
            bundle.count >= minimumPayloadBundleLength,
            bundle.first == payloadBundleVersion
        else {
            return nil
        }

        let nonceStart = 1
        let nonceEnd = nonceStart + aesGCMNonceLength
        let nonceData = bundle.subdata(in: nonceStart..<nonceEnd)
        let encryptedAndTag = bundle.suffix(from: nonceEnd)
        guard encryptedAndTag.count >= aesGCMTagLength else {
            return nil
        }

        let ciphertextData = encryptedAndTag.dropLast(aesGCMTagLength)
        let tagData = encryptedAndTag.suffix(aesGCMTagLength)
        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealed = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: Data(ciphertextData),
                tag: Data(tagData)
            )
            let key = SymmetricKey(data: keyData)
            return try AES.GCM.open(sealed, using: key)
        } catch {
            return nil
        }
    }

}
