import Foundation
import CryptoKit
import CoreKit

public enum NewSessionMachinePresentation {
    private static let accountSecretDefaultsKey = "unhappy.native.account.secret"
    private static let payloadBundleVersion: UInt8 = 2
    private static let wrappedDataKeyBundleVersion: UInt8 = 2
    private static let x25519PublicKeyLength = 32
    private static let aesGCMNonceLength = 12
    private static let aesGCMTagLength = 16
    private static let minimumPayloadBundleLength = 1 + aesGCMNonceLength + aesGCMTagLength
    private static let minimumWrappedDataKeyBundleLength =
        1 + x25519PublicKeyLength + aesGCMNonceLength + aesGCMTagLength
    private static let wrappedDataKeyKDFSalt =
        Data("unhappy.data.encryption-key.wrap.salt.v2".utf8)
    private static let wrappedDataKeyKDFInfo =
        Data("unhappy.data.encryption-key.wrap.info.v2".utf8)

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

        if let keyData = resolveDataEncryptionKey(raw: machine.dataEncryptionKey),
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

    private static func resolveDataEncryptionKey(raw: String?) -> Data? {
        guard let raw else { return nil }
        guard let decoded = decodeBase64(raw) else { return nil }
        guard
            let accountSecret = loadAccountSecret(),
            let contentSecret = deriveContentBoxSecretKey(fromAccountSecret: accountSecret)
        else {
            return nil
        }
        return decryptWrappedDataKey(bundle: decoded, secretKey: contentSecret)
    }

    private static func decryptWrappedDataKey(bundle: Data, secretKey: Data) -> Data? {
        guard
            secretKey.count == x25519PublicKeyLength,
            bundle.count >= minimumWrappedDataKeyBundleLength,
            bundle.first == wrappedDataKeyBundleVersion
        else {
            return nil
        }

        let ephemeralStart = 1
        let ephemeralEnd = ephemeralStart + x25519PublicKeyLength
        let nonceStart = ephemeralEnd
        let nonceEnd = nonceStart + aesGCMNonceLength

        let ephemeralPublicKeyData = bundle.subdata(in: ephemeralStart..<ephemeralEnd)
        let nonceData = bundle.subdata(in: nonceStart..<nonceEnd)
        let ciphertextAndTag = bundle.suffix(from: nonceEnd)

        guard let privateKey = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: secretKey),
              let ephemeralPublicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeralPublicKeyData),
              let sharedSecret = try? privateKey.sharedSecretFromKeyAgreement(with: ephemeralPublicKey) else {
            return nil
        }

        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: wrappedDataKeyKDFSalt,
            sharedInfo: wrappedDataKeyKDFInfo,
            outputByteCount: 32
        )

        guard let sealedBox = try? AES.GCM.SealedBox(combined: nonceData + ciphertextAndTag),
              let decrypted = try? AES.GCM.open(sealedBox, using: symmetricKey) else {
            return nil
        }

        return Data(decrypted)
    }

    private static func decryptDataKeyPayload(payload: String, keyData: Data) -> Data? {
        guard keyData.count == 32 else { return nil }
        guard let decoded = decodeBase64(payload) else { return nil }
        guard decoded.count >= minimumPayloadBundleLength else { return nil }
        guard decoded.first == payloadBundleVersion else { return nil }

        let nonceStart = 1
        let nonceEnd = nonceStart + aesGCMNonceLength
        let nonceData = decoded.subdata(in: nonceStart..<nonceEnd)
        let ciphertextAndTag = decoded.suffix(from: nonceEnd)

        let symmetricKey = SymmetricKey(data: keyData)
        guard let sealedBox = try? AES.GCM.SealedBox(combined: nonceData + ciphertextAndTag),
              let decrypted = try? AES.GCM.open(sealedBox, using: symmetricKey) else {
            return nil
        }

        return Data(decrypted)
    }

    private static func deriveContentBoxSecretKey(fromAccountSecret accountSecret: String) -> Data? {
        let normalized = accountSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decoded = Data(base64Encoded: normalized) ?? decodeBase64(normalized) else {
            return nil
        }
        return decoded.count == x25519PublicKeyLength ? decoded : nil
    }

    private static func loadAccountSecret() -> String? {
        let raw = UserDefaults.standard.string(forKey: accountSecretDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw?.isEmpty == false ? raw : nil
    }

    private static func decodeBase64(_ raw: String) -> Data? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        if let data = Data(base64Encoded: normalized) {
            return data
        }

        let rem = normalized.count % 4
        let padded = rem == 0 ? normalized : normalized + String(repeating: "=", count: 4 - rem)
        return Data(base64Encoded: padded)
    }

    private static func normalizeKey(_ raw: String) -> String {
        raw
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^A-Za-z0-9]", with: "", options: .regularExpression)
            .lowercased()
    }
}
