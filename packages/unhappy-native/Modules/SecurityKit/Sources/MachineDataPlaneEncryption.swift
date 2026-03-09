import CryptoKit
import Foundation
import Security

public enum SecurityKitError: Error {
    case invalidPayload
    case invalidKeyExchange
}

public struct MachineDataPlaneSessionHandshakeMaterial: Sendable {
    public let privateKey: Data
    public let publicKeyBase64URL: String
    public let nonceBase64URL: String

    public init(privateKey: Data, publicKeyBase64URL: String, nonceBase64URL: String) {
        self.privateKey = privateKey
        self.publicKeyBase64URL = publicKeyBase64URL
        self.nonceBase64URL = nonceBase64URL
    }
}

public struct MachineDataPlaneSealedPayload: Sendable, Equatable {
    public let algorithm: String
    public let nonce: String
    public let ciphertext: String
    public let tag: String

    public init(
        algorithm: String = "aes-256-gcm",
        nonce: String,
        ciphertext: String,
        tag: String
    ) {
        self.algorithm = algorithm
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
    }
}

public enum MachineDataPlaneEncryption {
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
    private static let sessionKeyInfo =
        Data("unhappy.machine-data-plane.session.v1".utf8)

    public static func resolveMachineDataKey(rawWrappedKey: String?) -> Data? {
        guard let rawWrappedKey else { return nil }
        guard let wrappedKey = decodeBase64(rawWrappedKey) else { return nil }
        guard
            let accountSecret = loadAccountSecret(),
            let contentSecret = deriveContentBoxSecretKey(fromAccountSecret: accountSecret)
        else {
            return nil
        }
        return decryptWrappedDataKey(bundle: wrappedKey, secretKey: contentSecret)
    }

    public static func encryptJSONPayload(_ object: Any, dataKey: Data) throws -> String {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw SecurityKitError.invalidPayload
        }

        let plaintext = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let symmetricKey = SymmetricKey(data: dataKey)
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(plaintext, using: symmetricKey, nonce: nonce)

        var bundle = Data([payloadBundleVersion])
        bundle.append(contentsOf: nonce)
        bundle.append(sealed.ciphertext)
        bundle.append(sealed.tag)
        return bundle.base64EncodedString()
    }

    public static func decryptJSONPayload(_ base64Bundle: String, dataKey: Data) throws -> Data {
        guard let bundle = decodeBase64(base64Bundle) else {
            throw SecurityKitError.invalidPayload
        }
        guard
            bundle.count >= minimumPayloadBundleLength,
            bundle.first == payloadBundleVersion
        else {
            throw SecurityKitError.invalidPayload
        }

        let nonceStart = 1
        let nonceEnd = nonceStart + aesGCMNonceLength
        let nonceData = bundle.subdata(in: nonceStart..<nonceEnd)
        let encryptedAndTag = bundle.suffix(from: nonceEnd)
        guard encryptedAndTag.count >= aesGCMTagLength else {
            throw SecurityKitError.invalidPayload
        }

        let ciphertextData = encryptedAndTag.dropLast(aesGCMTagLength)
        let tagData = encryptedAndTag.suffix(aesGCMTagLength)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealed = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: Data(ciphertextData),
            tag: Data(tagData)
        )
        return try AES.GCM.open(sealed, using: SymmetricKey(data: dataKey))
    }

    public static func generateSessionHandshakeMaterial() throws -> MachineDataPlaneSessionHandshakeMaterial {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let nonceData = try randomBytes(count: 32)
        return MachineDataPlaneSessionHandshakeMaterial(
            privateKey: privateKey.rawRepresentation,
            publicKeyBase64URL: Base64URLCodec.encode(privateKey.publicKey.rawRepresentation),
            nonceBase64URL: Base64URLCodec.encode(nonceData)
        )
    }

    public static func deriveSessionKey(
        machineDataKey: Data,
        localPrivateKey: Data,
        localNonceBase64URL: String,
        peerPublicKeyBase64URL: String,
        peerNonceBase64URL: String,
        role: String
    ) throws -> Data {
        guard machineDataKey.count == 32 else {
            throw SecurityKitError.invalidKeyExchange
        }
        guard let localNonce = Base64URLCodec.decode(localNonceBase64URL),
              let peerPublicKey = Base64URLCodec.decode(peerPublicKeyBase64URL),
              let peerNonce = Base64URLCodec.decode(peerNonceBase64URL),
              localNonce.count == 32,
              peerPublicKey.count == 32,
              peerNonce.count == 32 else {
            throw SecurityKitError.invalidKeyExchange
        }

        let localKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: localPrivateKey)
        let remoteKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey)
        let sharedSecret = try localKey.sharedSecretFromKeyAgreement(with: remoteKey)

        var inputKeyMaterial = Data()
        sharedSecret.withUnsafeBytes { buffer in
            inputKeyMaterial.append(contentsOf: buffer)
        }
        inputKeyMaterial.append(machineDataKey)

        let salt: Data
        if role == "native" {
            salt = localNonce + peerNonce
        } else {
            salt = peerNonce + localNonce
        }

        return hkdfSHA256(
            inputKeyMaterial: inputKeyMaterial,
            salt: salt,
            info: sessionKeyInfo,
            outputByteCount: 32
        )
    }

    public static func encryptDataPlaneJSONObject(
        _ object: Any,
        sessionKey: Data,
        authenticatedData: Data
    ) throws -> MachineDataPlaneSealedPayload {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw SecurityKitError.invalidPayload
        }
        let plaintext = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let nonceData = try randomBytes(count: aesGCMNonceLength)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealed = try AES.GCM.seal(
            plaintext,
            using: SymmetricKey(data: sessionKey),
            nonce: nonce,
            authenticating: authenticatedData
        )
        return MachineDataPlaneSealedPayload(
            nonce: Base64URLCodec.encode(nonceData),
            ciphertext: Base64URLCodec.encode(sealed.ciphertext),
            tag: Base64URLCodec.encode(sealed.tag)
        )
    }

    public static func decryptDataPlanePayload(
        _ sealedPayload: MachineDataPlaneSealedPayload,
        sessionKey: Data,
        authenticatedData: Data
    ) throws -> Data {
        guard let nonceData = Base64URLCodec.decode(sealedPayload.nonce),
              let ciphertext = Base64URLCodec.decode(sealedPayload.ciphertext),
              let tag = Base64URLCodec.decode(sealedPayload.tag),
              nonceData.count == aesGCMNonceLength,
              tag.count == aesGCMTagLength else {
            throw SecurityKitError.invalidPayload
        }
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealed = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: ciphertext,
            tag: tag
        )
        return try AES.GCM.open(
            sealed,
            using: SymmetricKey(data: sessionKey),
            authenticating: authenticatedData
        )
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

    private static func hmacSHA256(key: Data, data: Data) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(
            for: data,
            using: SymmetricKey(data: key)
        )
        return Data(mac)
    }

    private static func hkdfSHA256(
        inputKeyMaterial: Data,
        salt: Data,
        info: Data,
        outputByteCount: Int
    ) -> Data {
        let pseudoRandomKey = hmacSHA256(key: salt, data: inputKeyMaterial)
        var output = Data()
        var previous = Data()
        var counter: UInt8 = 1

        while output.count < outputByteCount {
            var blockInput = Data()
            blockInput.append(previous)
            blockInput.append(info)
            blockInput.append(counter)
            previous = hmacSHA256(key: pseudoRandomKey, data: blockInput)
            output.append(previous)
            counter &+= 1
        }

        return output.prefix(outputByteCount)
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

    private static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw SecurityKitError.invalidPayload
        }
        return Data(bytes)
    }
}
