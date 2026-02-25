import Foundation
import Security
import CoreKit
import TweetNacl

public struct AccountRestoreQRSession: Sendable, Equatable {
    public let publicKeyBase64: String
    public let secretKey: Data
    public let qrPayload: String

    public init(
        publicKeyBase64: String,
        secretKey: Data,
        qrPayload: String
    ) {
        self.publicKeyBase64 = publicKeyBase64
        self.secretKey = secretKey
        self.qrPayload = qrPayload
    }
}

public struct AccountRestoreQRCredentials: Sendable, Equatable {
    public let token: String
    public let secretBase64URL: String

    public init(token: String, secretBase64URL: String) {
        self.token = token
        self.secretBase64URL = secretBase64URL
    }
}

public enum AccountRestoreQRPollResult: Sendable, Equatable {
    case pending
    case authorized(AccountRestoreQRCredentials)
}

public enum AccountRestoreQRError: LocalizedError, Equatable {
    case invalidServerURL
    case keyGenerationFailed
    case invalidEncryptedPayload
    case decryptionFailed
    case missingTokenInResponse
    case invalidSecretInResponse
    case failed(message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Invalid server URL"
        case .keyGenerationFailed:
            return "Failed to generate account restore key"
        case .invalidEncryptedPayload:
            return "Invalid encrypted response payload"
        case .decryptionFailed:
            return "Failed to decrypt restore payload"
        case .missingTokenInResponse:
            return "Auth response is missing token"
        case .invalidSecretInResponse:
            return "Auth response has invalid account secret"
        case .failed(let message):
            return message
        }
    }
}

public protocol AccountQRRestoringAction: Sendable {
    func createSession() async throws -> AccountRestoreQRSession
    func pollStatus(
        serverURLString: String,
        session: AccountRestoreQRSession
    ) async throws -> AccountRestoreQRPollResult
}

public actor AccountRestoreQRUseCase: AccountQRRestoringAction {
    private let requestService: any AccountRestoreRequestPolling

    public init(requestService: any AccountRestoreRequestPolling) {
        self.requestService = requestService
    }

    public func createSession() async throws -> AccountRestoreQRSession {
        let seed = try randomBytes(count: 32)
        let keyPair: (publicKey: Data, secretKey: Data)
        do {
            keyPair = try NaclBox.keyPair(fromSecretKey: seed)
        } catch {
            throw AccountRestoreQRError.keyGenerationFailed
        }

        let publicKeyBase64 = keyPair.publicKey.base64EncodedString()
        let publicKeyBase64URL = Base64URLCodec.encode(keyPair.publicKey)
        return AccountRestoreQRSession(
            publicKeyBase64: publicKeyBase64,
            secretKey: keyPair.secretKey,
            qrPayload: "unhappy:///account?\(publicKeyBase64URL)"
        )
    }

    public func pollStatus(
        serverURLString: String,
        session: AccountRestoreQRSession
    ) async throws -> AccountRestoreQRPollResult {
        let serverURL = try parseServerURL(serverURLString)
        let status: APIAccountRestoreRequestStatus
        do {
            status = try await requestService.fetchAccountRestoreRequestStatus(
                serverURL: serverURL,
                publicKeyBase64: session.publicKeyBase64,
                supportsEncryptedToken: true
            )
        } catch let error as AccountRestoreRequestAPIError {
            throw AccountRestoreQRError.failed(message: error.localizedDescription)
        } catch {
            throw AccountRestoreQRError.failed(message: error.localizedDescription)
        }

        guard status.state.lowercased() == "authorized" else {
            return .pending
        }

        guard
            let encryptedSecretBase64 = status.response?.trimmingCharacters(in: .whitespacesAndNewlines),
            !encryptedSecretBase64.isEmpty
        else {
            throw AccountRestoreQRError.invalidEncryptedPayload
        }

        let secret = try decryptBundle(
            encryptedBundleBase64: encryptedSecretBase64,
            recipientSecretKey: session.secretKey
        )
        guard secret.count == 32 else {
            throw AccountRestoreQRError.invalidSecretInResponse
        }

        let token: String
        if let encryptedTokenBase64 = status.encryptedToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !encryptedTokenBase64.isEmpty {
            let tokenData = try decryptBundle(
                encryptedBundleBase64: encryptedTokenBase64,
                recipientSecretKey: session.secretKey
            )
            let decodedToken = String(data: tokenData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let decodedToken, !decodedToken.isEmpty else {
                throw AccountRestoreQRError.missingTokenInResponse
            }
            token = decodedToken
        } else {
            let plainToken = status.token?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let plainToken, !plainToken.isEmpty else {
                throw AccountRestoreQRError.missingTokenInResponse
            }
            token = plainToken
        }

        return .authorized(
            AccountRestoreQRCredentials(
                token: token,
                secretBase64URL: Base64URLCodec.encode(secret)
            )
        )
    }

    private func parseServerURL(_ raw: String) throws -> URL {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalized.isEmpty,
            let url = URL(string: normalized),
            url.scheme != nil,
            url.host != nil
        else {
            throw AccountRestoreQRError.invalidServerURL
        }
        return url
    }

    private func decryptBundle(
        encryptedBundleBase64: String,
        recipientSecretKey: Data
    ) throws -> Data {
        guard let bundle = Data(base64Encoded: encryptedBundleBase64), bundle.count > 56 else {
            throw AccountRestoreQRError.invalidEncryptedPayload
        }
        let ephemeralPublicKey = bundle.prefix(32)
        let nonce = bundle.dropFirst(32).prefix(24)
        let encryptedPayload = bundle.dropFirst(56)

        do {
            return try NaclBox.open(
                message: Data(encryptedPayload),
                nonce: Data(nonce),
                publicKey: Data(ephemeralPublicKey),
                secretKey: recipientSecretKey
            )
        } catch {
            throw AccountRestoreQRError.decryptionFailed
        }
    }
}

private func randomBytes(count: Int) throws -> Data {
    var bytes = [UInt8](repeating: 0, count: count)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard status == errSecSuccess else {
        throw AccountRestoreQRError.keyGenerationFailed
    }
    return Data(bytes)
}
