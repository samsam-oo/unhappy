import Foundation
import Testing
@testable import FeatureSettings
@testable import CoreKit

struct AccountLinkUseCaseTests {
    @Test
    func approveAccountLinkEncryptsSecretAndCallsService() async throws {
        let service = MockAccountAuthService()
        let encryptor = MockTerminalEncryptor(result: "encrypted-response")
        let useCase = AccountLinkUseCase(service: service, encryptor: encryptor)

        let publicKey = Data(repeating: 0x11, count: 32)
        let secret = Data(repeating: 0xAA, count: 32)
        let accountURL = "unhappy://account?\(asBase64URL(publicKey))"

        try await useCase.approveAccountLink(
            serverURLString: "https://api.unhappy.im",
            token: " token-123 ",
            accountSecretBase64URL: asBase64URL(secret),
            accountAuthURLString: accountURL
        )

        let call = await service.lastApproveCall
        #expect(call?.serverURL.absoluteString == "https://api.unhappy.im")
        #expect(call?.token == "token-123")
        #expect(call?.publicKeyBase64 == publicKey.base64EncodedString())
        #expect(call?.responseBase64 == "encrypted-response")

        let recorded = encryptor.lastCall
        #expect(recorded?.message == secret)
        #expect(recorded?.recipientPublicKeyBase64URL == asBase64URL(publicKey))
    }

    @Test
    func approveAccountLinkRejectsMissingSecret() async {
        let useCase = AccountLinkUseCase(
            service: MockAccountAuthService(),
            encryptor: MockTerminalEncryptor(result: "ignored")
        )

        await #expect(throws: AccountLinkError.missingAccountSecret) {
            try await useCase.approveAccountLink(
                serverURLString: "https://api.unhappy.im",
                token: "token",
                accountSecretBase64URL: " ",
                accountAuthURLString: "unhappy://account?abc123"
            )
        }
    }

    @Test
    func approveAccountLinkRejectsInvalidAccountURL() async {
        let useCase = AccountLinkUseCase(
            service: MockAccountAuthService(),
            encryptor: MockTerminalEncryptor(result: "ignored")
        )

        await #expect(throws: AccountLinkError.invalidAccountAuthURL) {
            try await useCase.approveAccountLink(
                serverURLString: "https://api.unhappy.im",
                token: "token",
                accountSecretBase64URL: asBase64URL(Data(repeating: 0x01, count: 32)),
                accountAuthURLString: "unhappy://terminal?abc123"
            )
        }
    }

    @Test
    func approveAccountLinkMapsAPIErrorToFailedMessage() async {
        let service = MockAccountAuthService(error: AccountAuthAPIError.invalidHTTPStatus(500))
        let useCase = AccountLinkUseCase(
            service: service,
            encryptor: MockTerminalEncryptor(result: "encrypted-response")
        )

        let publicKey = Data(repeating: 0x11, count: 32)
        await #expect(throws: AccountLinkError.failed(message: "Request failed with status 500")) {
            try await useCase.approveAccountLink(
                serverURLString: "https://api.unhappy.im",
                token: "token",
                accountSecretBase64URL: asBase64URL(Data(repeating: 0x01, count: 32)),
                accountAuthURLString: "unhappy://account?\(asBase64URL(publicKey))"
            )
        }
    }
}

private actor MockAccountAuthService: AccountAuthResponding {
    struct ApproveCall: Equatable {
        let serverURL: URL
        let token: String
        let publicKeyBase64: String
        let responseBase64: String
    }

    private(set) var lastApproveCall: ApproveCall?
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func approveAccountRequest(
        serverURL: URL,
        token: String,
        publicKeyBase64: String,
        responseBase64: String
    ) async throws {
        if let error {
            throw error
        }
        lastApproveCall = ApproveCall(
            serverURL: serverURL,
            token: token,
            publicKeyBase64: publicKeyBase64,
            responseBase64: responseBase64
        )
    }
}

private final class MockTerminalEncryptor: TerminalAuthEncrypting, @unchecked Sendable {
    struct EncryptCall: Equatable {
        let message: Data
        let recipientPublicKeyBase64URL: String
    }

    private let lock = NSLock()
    private let result: String
    private(set) var lastCall: EncryptCall?

    init(result: String) {
        self.result = result
    }

    func encrypt(message: Data, recipientPublicKeyBase64URL: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        lastCall = EncryptCall(
            message: message,
            recipientPublicKeyBase64URL: recipientPublicKeyBase64URL
        )
        return result
    }
}

private func asBase64URL(_ value: Data) -> String {
    value.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
