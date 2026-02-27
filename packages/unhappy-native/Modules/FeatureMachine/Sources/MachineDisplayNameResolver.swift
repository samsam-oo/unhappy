import Foundation
import CryptoKit
import CoreKit

enum MachineDisplayNameResolver {
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

    static func displayName(for machine: APIMachine) -> String {
        guard let metadata = parseJSONObject(
            raw: machine.metadata,
            dataEncryptionKey: machine.dataEncryptionKey
        ) else {
            return machine.id
        }

        if let name = firstString(in: metadata, keys: ["displayName", "name", "machineName"]) {
            return name
        }
        if let host = firstString(in: metadata, keys: ["host", "hostname", "computerName"]) {
            return host
        }
        return machine.id
    }

    private static func parseJSONObject(
        raw: String,
        dataEncryptionKey: String?
    ) -> [String: Any]? {
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

        if let decrypted = decryptDataKeyPayload(
            payload: payload,
            dataEncryptionKey: dataEncryptionKey
        ),
           let object = try? JSONSerialization.jsonObject(with: decrypted),
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
            return normalizeDisplayValue(string)
        }
        if let number = value as? NSNumber {
            return normalizeDisplayValue(number.stringValue)
        }
        return nil
    }

    private static func normalizeDisplayValue(_ raw: String) -> String? {
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
        guard !blockedValues.contains(lowered) else { return nil }
        return withoutLocalSuffix
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

    private static func decryptDataKeyPayload(
        payload: String,
        dataEncryptionKey: String?
    ) -> Data? {
        guard let keyData = resolveDataEncryptionKey(raw: dataEncryptionKey), keyData.count == 32 else {
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
        let encryptedAndTag = bundle.suffix(from: nonceEnd)
        guard encryptedAndTag.count >= aesGCMTagLength else {
            return nil
        }

        let ciphertextData = encryptedAndTag.dropLast(aesGCMTagLength)
        let tagData = encryptedAndTag.suffix(aesGCMTagLength)
        do {
            let recipientPrivateKey = try Curve25519.KeyAgreement.PrivateKey(
                rawRepresentation: secretKey
            )
            let ephemeralPublicKey = try Curve25519.KeyAgreement.PublicKey(
                rawRepresentation: ephemeralPublicKeyData
            )
            let sharedSecret = try recipientPrivateKey.sharedSecretFromKeyAgreement(
                with: ephemeralPublicKey
            )
            let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: wrappedDataKeyKDFSalt,
                sharedInfo: wrappedDataKeyKDFInfo,
                outputByteCount: 32
            )
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealed = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: Data(ciphertextData),
                tag: Data(tagData)
            )
            let opened = try AES.GCM.open(sealed, using: symmetricKey)
            return opened.count == 32 ? opened : nil
        } catch {
            return nil
        }
    }

    private static func loadAccountSecret() -> Data? {
        let raw = UserDefaults.standard
            .string(forKey: accountSecretDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        guard let decoded = decodeBase64(raw), decoded.count == 32 else {
            return nil
        }
        return decoded
    }

    private static func deriveContentBoxSecretKey(fromAccountSecret accountSecret: Data) -> Data? {
        guard accountSecret.count == 32 else { return nil }
        guard let contentSeed = deriveKey(
            master: accountSecret,
            usage: "Unhappy EnCoder",
            path: ["content"]
        ) else {
            return nil
        }
        return deriveCurve25519SecretKey(fromSeed: contentSeed)
    }

    private static func deriveKey(master: Data, usage: String, path: [String]) -> Data? {
        let rootInput = Data("\(usage) Master Seed".utf8)
        let rootDigest = hmacSHA512(key: master, data: rootInput)
        guard rootDigest.count == 64 else { return nil }

        var key = Data(rootDigest.prefix(32))
        var chainCode = Data(rootDigest.suffix(32))
        for index in path {
            var childInput = Data([0x00])
            childInput.append(Data(index.utf8))
            let childDigest = hmacSHA512(key: chainCode, data: childInput)
            guard childDigest.count == 64 else { return nil }
            key = Data(childDigest.prefix(32))
            chainCode = Data(childDigest.suffix(32))
        }
        return key
    }

    private static func hmacSHA512(key: Data, data: Data) -> Data {
        let mac = HMAC<SHA512>.authenticationCode(
            for: data,
            using: SymmetricKey(data: key)
        )
        return Data(mac)
    }

    private static func deriveCurve25519SecretKey(fromSeed seed: Data) -> Data? {
        guard seed.count == 32 else { return nil }
        let digest = SHA512.hash(data: seed)
        var scalar = Array(digest.prefix(32))
        guard scalar.count == 32 else { return nil }

        scalar[0] &= 248
        scalar[31] &= 127
        scalar[31] |= 64
        return Data(scalar)
    }
}
