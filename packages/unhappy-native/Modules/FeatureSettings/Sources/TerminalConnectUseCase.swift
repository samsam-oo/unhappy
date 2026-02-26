import Foundation
import Security
import CoreKit
import TweetNacl

public enum TerminalConnectRequestState: Equatable, Sendable {
    case pending(supportsV2: Bool)
    case authorized
}

public enum TerminalConnectError: LocalizedError, Equatable {
    case missingToken
    case invalidServerURL
    case invalidPublicKey
    case requestNotFound
    case keyGenerationFailed
    case encryptionFailed
    case failed(message: String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .invalidServerURL:
            return "Invalid server URL"
        case .invalidPublicKey:
            return "Invalid terminal public key"
        case .requestNotFound:
            return "Terminal auth request not found or expired"
        case .keyGenerationFailed:
            return "Failed to generate terminal data key"
        case .encryptionFailed:
            return "Failed to encrypt terminal approval payload"
        case .failed(let message):
            return message
        }
    }
}

public protocol TerminalDataKeyStoring: Sendable {
    func loadOrCreateDataKey() async throws -> Data
}

public protocol TerminalAuthEncrypting: Sendable {
    func encrypt(message: Data, recipientPublicKeyBase64URL: String) throws -> String
}

public protocol TerminalConnectingAction: Sendable {
    func fetchRequestState(
        serverURLString: String,
        publicKeyBase64URL: String
    ) async throws -> TerminalConnectRequestState

    func approveRequest(
        serverURLString: String,
        token: String,
        publicKeyBase64URL: String
    ) async throws -> TerminalConnectRequestState
}

public actor UserDefaultsTerminalDataKeyStore: TerminalDataKeyStoring {
    private let defaults: UserDefaults
    private let contentDataKeyStorageKey: String

    public init(
        defaults: UserDefaults = .standard,
        contentDataKeyStorageKey: String = "unhappy.native.terminal.contentDataKey"
    ) {
        self.defaults = defaults
        self.contentDataKeyStorageKey = contentDataKeyStorageKey
    }

    public func loadOrCreateDataKey() async throws -> Data {
        if let encoded = defaults.string(forKey: contentDataKeyStorageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !encoded.isEmpty,
           let existing = Data(base64Encoded: encoded),
           existing.count == 32 {
            return existing
        }

        let generated = try randomBytes(count: 32)
        defaults.set(generated.base64EncodedString(), forKey: contentDataKeyStorageKey)
        return generated
    }
}

public struct TweetNaclTerminalAuthEncryptor: TerminalAuthEncrypting {
    public init() {}

    public func encrypt(message: Data, recipientPublicKeyBase64URL: String) throws -> String {
        guard
            let recipientPublicKey = Base64URLCodec.decode(recipientPublicKeyBase64URL),
            recipientPublicKey.count == 32
        else {
            throw TerminalConnectError.invalidPublicKey
        }

        do {
            let ephemeralKeyPair = try NaclBox.keyPair()
            let nonce = try randomBytes(count: 24)
            let encrypted = try NaclBox.box(
                message: message,
                nonce: nonce,
                publicKey: recipientPublicKey,
                secretKey: ephemeralKeyPair.secretKey
            )

            var bundle = Data()
            bundle.append(ephemeralKeyPair.publicKey)
            bundle.append(nonce)
            bundle.append(encrypted)
            return bundle.base64EncodedString()
        } catch {
            throw TerminalConnectError.encryptionFailed
        }
    }
}

public actor TerminalConnectUseCase: TerminalConnectingAction {
    private let service: any TerminalAuthStatusChecking & TerminalAuthResponding
    private let dataKeyStore: any TerminalDataKeyStoring
    private let encryptor: any TerminalAuthEncrypting

    public init(
        service: any TerminalAuthStatusChecking & TerminalAuthResponding,
        dataKeyStore: any TerminalDataKeyStoring,
        encryptor: any TerminalAuthEncrypting
    ) {
        self.service = service
        self.dataKeyStore = dataKeyStore
        self.encryptor = encryptor
    }

    public func fetchRequestState(
        serverURLString: String,
        publicKeyBase64URL: String
    ) async throws -> TerminalConnectRequestState {
        let serverURL = try parseServerURL(serverURLString)
        let normalizedPublicKey = normalizePublicKey(publicKeyBase64URL)
        let publicKeyBase64 = try toStandardBase64(normalizedPublicKey)

        let status = try await service.fetchRequestStatus(
            serverURL: serverURL,
            publicKeyBase64: publicKeyBase64
        )
        return try mapStatus(status)
    }

    public func approveRequest(
        serverURLString: String,
        token: String,
        publicKeyBase64URL: String
    ) async throws -> TerminalConnectRequestState {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw TerminalConnectError.missingToken
        }

        let serverURL = try parseServerURL(serverURLString)
        let normalizedPublicKey = normalizePublicKey(publicKeyBase64URL)
        let publicKeyBase64 = try toStandardBase64(normalizedPublicKey)

        let status = try await service.fetchRequestStatus(
            serverURL: serverURL,
            publicKeyBase64: publicKeyBase64
        )

        switch status.status {
        case .notFound:
            throw TerminalConnectError.requestNotFound
        case .authorized:
            return .authorized
        case .pending:
            let dataKey = try await dataKeyStore.loadOrCreateDataKey()
            let payload: Data
            if status.supportsV2 {
                var bundle = Data([0])
                bundle.append(dataKey)
                payload = bundle
            } else {
                payload = dataKey
            }

            let encryptedResponse = try encryptor.encrypt(
                message: payload,
                recipientPublicKeyBase64URL: normalizedPublicKey
            )
            let approvalResult = try await service.approveRequest(
                serverURL: serverURL,
                token: normalizedToken,
                publicKeyBase64: publicKeyBase64,
                responseBase64: encryptedResponse
            )
            if !approvalResult.success {
                let normalizedError = approvalResult.error?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw TerminalConnectError.failed(
                    message: (normalizedError?.isEmpty == false ? normalizedError : nil)
                        ?? "Terminal approval failed"
                )
            }

            let nextStatus = try await service.fetchRequestStatus(
                serverURL: serverURL,
                publicKeyBase64: publicKeyBase64
            )
            return try mapStatus(nextStatus)
        }
    }

    private func mapStatus(_ status: APITerminalAuthStatus) throws -> TerminalConnectRequestState {
        switch status.status {
        case .notFound:
            throw TerminalConnectError.requestNotFound
        case .pending:
            return .pending(supportsV2: status.supportsV2)
        case .authorized:
            return .authorized
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
            throw TerminalConnectError.invalidServerURL
        }
        return url
    }

    private func normalizePublicKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func toStandardBase64(_ base64URL: String) throws -> String {
        guard let decoded = Base64URLCodec.decode(base64URL) else {
            throw TerminalConnectError.invalidPublicKey
        }
        return decoded.base64EncodedString()
    }
}

private func randomBytes(count: Int) throws -> Data {
    var bytes = [UInt8](repeating: 0, count: count)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard status == errSecSuccess else {
        throw TerminalConnectError.keyGenerationFailed
    }
    return Data(bytes)
}
