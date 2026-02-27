import Foundation
import CryptoKit
import CoreKit

public enum TerminalConnectRequestState: Equatable, Sendable {
    case pending(supportsV2: Bool)
    case authorized
}

public enum TerminalConnectError: LocalizedError, Equatable {
    case missingToken
    case missingAccountSecret
    case invalidAccountSecret
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
        case .missingAccountSecret:
            return "Account secret key is required"
        case .invalidAccountSecret:
            return "Invalid account secret key"
        case .invalidServerURL:
            return "Invalid server URL"
        case .invalidPublicKey:
            return "Invalid terminal public key"
        case .requestNotFound:
            return "Terminal auth request not found or expired"
        case .keyGenerationFailed:
            return "Failed to derive terminal content key"
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
    private let accountSecretStore: any AccountSecretStoring

    public init(
        defaults: UserDefaults = .standard,
        contentDataKeyStorageKey: String = "unhappy.native.terminal.contentDataKey",
        accountSecretStore: (any AccountSecretStoring)? = nil
    ) {
        _ = contentDataKeyStorageKey
        self.accountSecretStore = accountSecretStore ?? UserDefaultsAccountSecretStore(defaults: defaults)
    }

    public func loadOrCreateDataKey() async throws -> Data {
        let rawSecret = await accountSecretStore.loadSecretBase64URL()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !rawSecret.isEmpty else {
            throw TerminalConnectError.missingAccountSecret
        }
        guard let accountSecret = AccountSecretCodec.decode(rawSecret), accountSecret.count == 32 else {
            throw TerminalConnectError.invalidAccountSecret
        }
        guard
            let contentSeed = deriveKey(
                master: accountSecret,
                usage: "Unhappy EnCoder",
                path: ["content"]
            ),
            let contentPublicKey = deriveCurve25519PublicKey(fromSeed: contentSeed)
        else {
            throw TerminalConnectError.keyGenerationFailed
        }
        return contentPublicKey
    }
}

public struct CryptoKitTerminalAuthEncryptor: TerminalAuthEncrypting {
    public init() {}

    public func encrypt(message: Data, recipientPublicKeyBase64URL: String) throws -> String {
        guard
            let recipientPublicKey = Base64URLCodec.decode(recipientPublicKeyBase64URL),
            recipientPublicKey.count == 32
        else {
            throw TerminalConnectError.invalidPublicKey
        }

        do {
            let bundle = try AuthEnvelopeCrypto.encrypt(
                message: message,
                recipientPublicKey: recipientPublicKey
            )
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

private struct KeyTreeState {
    let key: Data
    let chainCode: Data
}

private func deriveKey(master: Data, usage: String, path: [String]) -> Data? {
    let rootInput = Data("\(usage) Master Seed".utf8)
    let rootDigest = hmacSHA512(key: master, data: rootInput)
    guard rootDigest.count == 64 else { return nil }

    var state = KeyTreeState(
        key: Data(rootDigest.prefix(32)),
        chainCode: Data(rootDigest.suffix(32))
    )

    for index in path {
        var childInput = Data([0x00])
        childInput.append(Data(index.utf8))
        let childDigest = hmacSHA512(key: state.chainCode, data: childInput)
        guard childDigest.count == 64 else { return nil }
        state = KeyTreeState(
            key: Data(childDigest.prefix(32)),
            chainCode: Data(childDigest.suffix(32))
        )
    }

    return state.key
}

private func hmacSHA512(key: Data, data: Data) -> Data {
    let mac = HMAC<SHA512>.authenticationCode(
        for: data,
        using: SymmetricKey(data: key)
    )
    return Data(mac)
}

private func deriveCurve25519PublicKey(fromSeed seed: Data) -> Data? {
    guard let secretKey = deriveCurve25519SecretKey(fromSeed: seed) else {
        return nil
    }
    guard let privateKey = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: secretKey) else {
        return nil
    }
    return privateKey.publicKey.rawRepresentation
}

private func deriveCurve25519SecretKey(fromSeed seed: Data) -> Data? {
    guard seed.count == 32 else { return nil }
    let digest = SHA512.hash(data: seed)
    var scalar = Array(digest.prefix(32))
    guard scalar.count == 32 else { return nil }

    scalar[0] &= 248
    scalar[31] &= 127
    scalar[31] |= 64
    return Data(scalar)
}
