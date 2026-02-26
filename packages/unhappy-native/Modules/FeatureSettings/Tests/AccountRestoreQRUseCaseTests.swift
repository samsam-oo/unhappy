import Foundation
import Testing
import CoreKit
import TweetNacl
@testable import FeatureSettings

struct AccountRestoreQRUseCaseTests {
    @Test
    func createSessionReturnsQRCodePayload() async throws {
        let useCase = AccountRestoreQRUseCase(requestService: MockAccountRestoreRequestService())

        let session = try await useCase.createSession()

        #expect(!session.publicKeyBase64.isEmpty)
        #expect(session.secretKey.count == 32)
        #expect(session.qrPayload.hasPrefix("unhappy:///account?"))
    }

    @Test
    func pollStatusReturnsPendingForNonAuthorizedState() async throws {
        let service = MockAccountRestoreRequestService(
            status: APIAccountRestoreRequestStatus(
                state: "pending",
                response: nil,
                token: nil,
                encryptedToken: nil
            )
        )
        let useCase = AccountRestoreQRUseCase(requestService: service)

        let result = try await useCase.pollStatus(
            serverURLString: "https://api.unhappy.im",
            session: try makeSession(secretSeed: Data(repeating: 7, count: 32))
        )

        #expect(result == .pending)
    }

    @Test
    func pollStatusDecryptsEncryptedSecretAndToken() async throws {
        let session = try makeSession(secretSeed: Data(repeating: 5, count: 32))
        let keyPair = try NaclBox.keyPair(fromSecretKey: session.secretKey)
        let restoredSecret = Data(repeating: 0xAA, count: 32)
        let encryptedSecret = try makeEncryptedBundle(
            message: restoredSecret,
            recipientPublicKey: keyPair.publicKey
        )
        let encryptedToken = try makeEncryptedBundle(
            message: Data("qr-restored-token".utf8),
            recipientPublicKey: keyPair.publicKey
        )
        let service = MockAccountRestoreRequestService(
            status: APIAccountRestoreRequestStatus(
                state: "authorized",
                response: encryptedSecret.base64EncodedString(),
                token: nil,
                encryptedToken: encryptedToken.base64EncodedString()
            )
        )
        let useCase = AccountRestoreQRUseCase(requestService: service)

        let result = try await useCase.pollStatus(
            serverURLString: "https://api.unhappy.im",
            session: session
        )

        #expect(
            result == .authorized(
                AccountRestoreQRCredentials(
                    token: "qr-restored-token",
                    secretBase64URL: Base64URLCodec.encode(restoredSecret)
                )
            )
        )
    }

    @Test
    func pollStatusUsesPlainTokenWhenEncryptedTokenMissing() async throws {
        let session = try makeSession(secretSeed: Data(repeating: 6, count: 32))
        let keyPair = try NaclBox.keyPair(fromSecretKey: session.secretKey)
        let restoredSecret = Data(repeating: 0xAB, count: 32)
        let encryptedSecret = try makeEncryptedBundle(
            message: restoredSecret,
            recipientPublicKey: keyPair.publicKey
        )
        let service = MockAccountRestoreRequestService(
            status: APIAccountRestoreRequestStatus(
                state: "authorized",
                response: encryptedSecret.base64EncodedString(),
                token: "plain-token",
                encryptedToken: nil
            )
        )
        let useCase = AccountRestoreQRUseCase(requestService: service)

        let result = try await useCase.pollStatus(
            serverURLString: "https://api.unhappy.im",
            session: session
        )

        #expect(
            result == .authorized(
                AccountRestoreQRCredentials(
                    token: "plain-token",
                    secretBase64URL: Base64URLCodec.encode(restoredSecret)
                )
            )
        )
    }
}

private actor MockAccountRestoreRequestService: AccountRestoreRequestPolling {
    private let status: APIAccountRestoreRequestStatus

    init(
        status: APIAccountRestoreRequestStatus = APIAccountRestoreRequestStatus(
            state: "pending",
            response: nil,
            token: nil,
            encryptedToken: nil
        )
    ) {
        self.status = status
    }

    func fetchAccountRestoreRequestStatus(
        serverURL: URL,
        publicKeyBase64: String,
        supportsEncryptedToken: Bool
    ) async throws -> APIAccountRestoreRequestStatus {
        status
    }
}

private func makeSession(secretSeed: Data) throws -> AccountRestoreQRSession {
    let keyPair = try NaclBox.keyPair(fromSecretKey: secretSeed)
    return AccountRestoreQRSession(
        publicKeyBase64: keyPair.publicKey.base64EncodedString(),
        secretKey: keyPair.secretKey,
        qrPayload: "unhappy:///account?\(Base64URLCodec.encode(keyPair.publicKey))"
    )
}

private func makeEncryptedBundle(message: Data, recipientPublicKey: Data) throws -> Data {
    let ephemeral = try NaclBox.keyPair()
    let nonce = Data((0..<24).map { UInt8(($0 * 3) % 255) })
    let encrypted = try NaclBox.box(
        message: message,
        nonce: nonce,
        publicKey: recipientPublicKey,
        secretKey: ephemeral.secretKey
    )

    var bundle = Data()
    bundle.append(ephemeral.publicKey)
    bundle.append(nonce)
    bundle.append(encrypted)
    return bundle
}
