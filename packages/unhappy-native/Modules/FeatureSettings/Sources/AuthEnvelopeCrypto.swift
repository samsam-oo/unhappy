import CryptoKit
import Foundation
import Security

enum AuthEnvelopeCryptoError: Error {
    case invalidPublicKey
    case invalidPrivateKey
    case invalidBundle
    case unsupportedVersion
    case encryptionFailed
    case decryptionFailed
    case randomGenerationFailed
}

struct AuthEnvelopeKeyPair: Sendable {
    let publicKey: Data
    let privateKey: Data
}

enum AuthEnvelopeCrypto {
    static let version: UInt8 = 1
    static let publicKeyLength = 32
    static let nonceLength = 12
    static let tagLength = 16
    static let minimumBundleLength = 1 + publicKeyLength + nonceLength + tagLength

    private static let kdfSalt = Data("unhappy.auth.envelope.salt.v1".utf8)
    private static let kdfInfo = Data("unhappy.auth.envelope.info.v1".utf8)

    static func generateKeyPair() throws -> AuthEnvelopeKeyPair {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        return AuthEnvelopeKeyPair(
            publicKey: privateKey.publicKey.rawRepresentation,
            privateKey: privateKey.rawRepresentation
        )
    }

    static func encrypt(message: Data, recipientPublicKey: Data) throws -> Data {
        guard recipientPublicKey.count == publicKeyLength else {
            throw AuthEnvelopeCryptoError.invalidPublicKey
        }

        do {
            let recipientKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientPublicKey)
            let ephemeralPrivateKey = Curve25519.KeyAgreement.PrivateKey()
            let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: recipientKey)
            let symmetricKey = deriveSymmetricKey(from: sharedSecret)
            let nonceData = try randomBytes(count: nonceLength)
            let nonce = try ChaChaPoly.Nonce(data: nonceData)
            let sealedBox = try ChaChaPoly.seal(message, using: symmetricKey, nonce: nonce)

            var bundle = Data()
            bundle.append(version)
            bundle.append(ephemeralPrivateKey.publicKey.rawRepresentation)
            bundle.append(nonceData)
            bundle.append(sealedBox.ciphertext)
            bundle.append(sealedBox.tag)
            return bundle
        } catch let error as AuthEnvelopeCryptoError {
            throw error
        } catch {
            throw AuthEnvelopeCryptoError.encryptionFailed
        }
    }

    static func decrypt(bundle: Data, recipientPrivateKey: Data) throws -> Data {
        guard recipientPrivateKey.count == publicKeyLength else {
            throw AuthEnvelopeCryptoError.invalidPrivateKey
        }
        guard bundle.count >= minimumBundleLength else {
            throw AuthEnvelopeCryptoError.invalidBundle
        }
        guard bundle.first == version else {
            throw AuthEnvelopeCryptoError.unsupportedVersion
        }

        let ephemeralStart = 1
        let ephemeralEnd = ephemeralStart + publicKeyLength
        let nonceStart = ephemeralEnd
        let nonceEnd = nonceStart + nonceLength

        let ephemeralPublicKeyData = bundle.subdata(in: ephemeralStart..<ephemeralEnd)
        let nonceData = bundle.subdata(in: nonceStart..<nonceEnd)
        let encryptedAndTag = bundle.suffix(from: nonceEnd)

        guard encryptedAndTag.count >= tagLength else {
            throw AuthEnvelopeCryptoError.invalidBundle
        }

        let ciphertext = encryptedAndTag.dropLast(tagLength)
        let tag = encryptedAndTag.suffix(tagLength)

        do {
            let recipientKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: recipientPrivateKey)
            let ephemeralKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeralPublicKeyData)
            let sharedSecret = try recipientKey.sharedSecretFromKeyAgreement(with: ephemeralKey)
            let symmetricKey = deriveSymmetricKey(from: sharedSecret)
            let nonce = try ChaChaPoly.Nonce(data: nonceData)
            let sealedBox = try ChaChaPoly.SealedBox(
                nonce: nonce,
                ciphertext: Data(ciphertext),
                tag: Data(tag)
            )
            return try ChaChaPoly.open(sealedBox, using: symmetricKey)
        } catch let error as AuthEnvelopeCryptoError {
            throw error
        } catch {
            throw AuthEnvelopeCryptoError.decryptionFailed
        }
    }

    private static func deriveSymmetricKey(from sharedSecret: SharedSecret) -> SymmetricKey {
        sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: kdfSalt,
            sharedInfo: kdfInfo,
            outputByteCount: 32
        )
    }

    private static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw AuthEnvelopeCryptoError.randomGenerationFailed
        }
        return Data(bytes)
    }
}
