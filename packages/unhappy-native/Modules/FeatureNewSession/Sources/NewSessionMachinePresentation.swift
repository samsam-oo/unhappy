import Foundation
import CryptoKit
import CoreKit
import SecurityKit

public enum NewSessionMachinePresentation {
    private static let payloadBundleVersion: UInt8 = 2
    private static let aesGCMNonceLength = 12
    private static let aesGCMTagLength = 16
    private static let minimumPayloadBundleLength = 1 + aesGCMNonceLength + aesGCMTagLength

    public static func displayName(for machine: APIMachine) -> String {
        let metadata = decodeMetadata(machine: machine)
        let primaryNameKeys = [
            "displayName", "name", "machineName", "deviceName", "computerName",
        ]
        let hostKeys = [
            "host", "hostname", "computerName", "localHostName", "hostName", "machineHost",
        ]

        if let name = bestDisplayString(
            in: metadata,
            keys: primaryNameKeys,
            rejectGenericHosts: true
        ) {
            return name
        }
        if let host = bestDisplayString(
            in: metadata,
            keys: hostKeys,
            rejectGenericHosts: true
        ) {
            return host
        }
        if let relaxedHost = bestDisplayString(
            in: metadata,
            keys: hostKeys,
            rejectGenericHosts: false
        ) {
            return relaxedHost
        }
        return machine.id
    }

    private static func decodeMetadata(machine: APIMachine) -> [String: Any] {
        let payload = machine.metadata.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else {
            return [:]
        }

        if let parsed = parseJSONObject(fromUTF8String: payload) {
            return parsed
        }

        if let keyData = MachineDataPlaneEncryption.resolveMachineDataKey(
            rawWrappedKey: machine.dataEncryptionKey,
            machineID: machine.id
        ),
           let decrypted = decryptDataKeyPayload(payload: payload, keyData: keyData),
           let parsed = parseJSONObject(fromData: decrypted) {
            return parsed
        }

        if let decoded = decodeBase64(payload),
           let parsed = parseJSONObject(fromData: decoded) {
            return parsed
        }

        return [:]
    }

    private static func bestDisplayString(
        in object: Any,
        keys: [String],
        rejectGenericHosts: Bool
    ) -> String? {
        let normalizedKeys = Set(keys.map(normalizeKey))
        let candidates = values(in: object, matching: normalizedKeys)
        for candidate in candidates {
            if let normalized = normalizeDisplayValue(
                candidate,
                rejectGenericHosts: rejectGenericHosts
            ) {
                return normalized
            }
        }
        return nil
    }

    private static func normalizeDisplayValue(
        _ raw: String,
        rejectGenericHosts: Bool
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
        return withoutLocalSuffix
    }

    private static func values(in object: Any, matching keys: Set<String>) -> [String] {
        var output: [String] = []
        collectValues(in: object, matching: keys, output: &output)
        return output
    }

    private static func collectValues(
        in object: Any,
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

    private static func parseJSONObject(fromUTF8String string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8) else { return nil }
        return parseJSONObject(fromData: data)
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

    private static func decryptDataKeyPayload(payload: String, keyData: Data) -> Data? {
        guard keyData.count == 32 else {
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

    private static func normalizeKey(_ key: String) -> String {
        String(key.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
