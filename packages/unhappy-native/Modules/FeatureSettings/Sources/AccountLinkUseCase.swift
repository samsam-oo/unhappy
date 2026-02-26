import Foundation
import CoreKit

public enum AccountLinkError: LocalizedError, Equatable {
    case missingToken
    case missingAccountSecret
    case invalidServerURL
    case invalidAccountAuthURL
    case invalidAccountSecret
    case invalidPublicKey
    case encryptionFailed
    case failed(message: String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .missingAccountSecret:
            return "Account secret key is required"
        case .invalidServerURL:
            return "Invalid server URL"
        case .invalidAccountAuthURL:
            return "Invalid account QR URL"
        case .invalidAccountSecret:
            return "Invalid account secret key"
        case .invalidPublicKey:
            return "Invalid account public key"
        case .encryptionFailed:
            return "Failed to encrypt account response"
        case .failed(let message):
            return message
        }
    }
}

public protocol AccountLinkingAction: Sendable {
    func approveAccountLink(
        serverURLString: String,
        token: String,
        accountSecretBase64URL: String,
        accountAuthURLString: String
    ) async throws
}

public actor AccountLinkUseCase: AccountLinkingAction {
    private let service: any AccountAuthResponding
    private let encryptor: any TerminalAuthEncrypting

    public init(
        service: any AccountAuthResponding,
        encryptor: any TerminalAuthEncrypting
    ) {
        self.service = service
        self.encryptor = encryptor
    }

    public func approveAccountLink(
        serverURLString: String,
        token: String,
        accountSecretBase64URL: String,
        accountAuthURLString: String
    ) async throws {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw AccountLinkError.missingToken
        }

        let normalizedSecret = accountSecretBase64URL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSecret.isEmpty else {
            throw AccountLinkError.missingAccountSecret
        }
        guard let secretData = AccountSecretCodec.decode(normalizedSecret), !secretData.isEmpty else {
            throw AccountLinkError.invalidAccountSecret
        }

        guard let request = AccountAuthURLParser.parse(accountAuthURLString) else {
            throw AccountLinkError.invalidAccountAuthURL
        }
        let normalizedPublicKey = request.publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let publicKeyData = Base64URLCodec.decode(normalizedPublicKey), !publicKeyData.isEmpty else {
            throw AccountLinkError.invalidPublicKey
        }

        let serverURL = try parseServerURL(serverURLString)
        let encryptedResponse: String
        do {
            encryptedResponse = try encryptor.encrypt(
                message: secretData,
                recipientPublicKeyBase64URL: normalizedPublicKey
            )
        } catch {
            throw AccountLinkError.encryptionFailed
        }

        do {
            try await service.approveAccountRequest(
                serverURL: serverURL,
                token: normalizedToken,
                publicKeyBase64: publicKeyData.base64EncodedString(),
                responseBase64: encryptedResponse
            )
        } catch let apiError as AccountAuthAPIError {
            throw AccountLinkError.failed(message: apiError.localizedDescription)
        } catch {
            throw AccountLinkError.failed(message: error.localizedDescription)
        }
    }

    private func parseServerURL(_ raw: String) throws -> URL {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalized.isEmpty,
            let url = URL(string: normalized),
            url.scheme != nil,
            url.host != nil
        else {
            throw AccountLinkError.invalidServerURL
        }
        return url
    }
}
