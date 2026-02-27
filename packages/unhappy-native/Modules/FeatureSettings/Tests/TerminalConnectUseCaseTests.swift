import Foundation
import Testing
import CoreKit
@testable import FeatureSettings

struct TerminalConnectUseCaseTests {
    @Test
    func fetchRequestStateReturnsPending() async throws {
        let publicKey = Data(repeating: 7, count: 32)
        let publicKeyBase64URL = asBase64URL(publicKey)
        let service = MockTerminalService(
            statuses: [
                APITerminalAuthStatus(status: .pending, supportsV2: true)
            ]
        )
        let useCase = TerminalConnectUseCase(
            service: service,
            dataKeyStore: MockDataKeyStore(dataKey: Data(repeating: 9, count: 32)),
            encryptor: MockEncryptor()
        )

        let state = try await useCase.fetchRequestState(
            serverURLString: "https://api.unhappy.im",
            publicKeyBase64URL: publicKeyBase64URL
        )

        #expect(state == .pending(supportsV2: true))
    }

    @Test
    func fetchRequestStateThrowsWhenRequestNotFound() async {
        let publicKey = Data(repeating: 4, count: 32)
        let service = MockTerminalService(
            statuses: [
                APITerminalAuthStatus(status: .notFound, supportsV2: false)
            ]
        )
        let useCase = TerminalConnectUseCase(
            service: service,
            dataKeyStore: MockDataKeyStore(dataKey: Data(repeating: 9, count: 32)),
            encryptor: MockEncryptor()
        )

        await #expect(throws: TerminalConnectError.requestNotFound) {
            _ = try await useCase.fetchRequestState(
                serverURLString: "https://api.unhappy.im",
                publicKeyBase64URL: asBase64URL(publicKey)
            )
        }
    }

    @Test
    func approveRequestEncryptsPayloadAndUpdatesState() async throws {
        let publicKey = Data(repeating: 11, count: 32)
        let publicKeyBase64URL = asBase64URL(publicKey)
        let storedDataKey = Data(repeating: 33, count: 32)
        let service = MockTerminalService(
            statuses: [
                APITerminalAuthStatus(status: .pending, supportsV2: true),
                APITerminalAuthStatus(status: .authorized, supportsV2: false)
            ],
            approveResult: APITerminalAuthApproveResult(success: true, error: nil)
        )
        let encryptor = MockEncryptor()
        let useCase = TerminalConnectUseCase(
            service: service,
            dataKeyStore: MockDataKeyStore(dataKey: storedDataKey),
            encryptor: encryptor
        )

        let state = try await useCase.approveRequest(
            serverURLString: "https://api.unhappy.im",
            token: "token-123",
            publicKeyBase64URL: publicKeyBase64URL
        )

        #expect(state == .authorized)

        let encryptedMessage = try #require(encryptor.lastMessage)
        #expect(encryptedMessage.first == 2)
        #expect(Data(encryptedMessage.dropFirst()) == storedDataKey)

        let approveCall = await service.lastApproveCall
        #expect(approveCall?.responseBase64 == "encrypted-bundle")
        #expect(approveCall?.publicKeyBase64 == publicKey.base64EncodedString())
    }

    @Test
    func approveRequestWithoutTokenThrowsValidationError() async {
        let publicKey = Data(repeating: 8, count: 32)
        let service = MockTerminalService(
            statuses: [
                APITerminalAuthStatus(status: .pending, supportsV2: true)
            ]
        )
        let useCase = TerminalConnectUseCase(
            service: service,
            dataKeyStore: MockDataKeyStore(dataKey: Data(repeating: 9, count: 32)),
            encryptor: MockEncryptor()
        )

        await #expect(throws: TerminalConnectError.missingToken) {
            _ = try await useCase.approveRequest(
                serverURLString: "https://api.unhappy.im",
                token: "   ",
                publicKeyBase64URL: asBase64URL(publicKey)
            )
        }
    }
}

private actor MockTerminalService: TerminalAuthStatusChecking, TerminalAuthResponding {
    struct ApproveCall: Equatable {
        let publicKeyBase64: String
        let responseBase64: String
    }

    private var statusQueue: [APITerminalAuthStatus]
    private let approveResult: APITerminalAuthApproveResult
    private(set) var lastApproveCall: ApproveCall?

    init(
        statuses: [APITerminalAuthStatus],
        approveResult: APITerminalAuthApproveResult = APITerminalAuthApproveResult(success: true, error: nil)
    ) {
        self.statusQueue = statuses
        self.approveResult = approveResult
        self.lastApproveCall = nil
    }

    func fetchRequestStatus(serverURL: URL, publicKeyBase64: String) async throws -> APITerminalAuthStatus {
        if statusQueue.isEmpty {
            return APITerminalAuthStatus(status: .notFound, supportsV2: false)
        }
        return statusQueue.removeFirst()
    }

    func approveRequest(
        serverURL: URL,
        token: String,
        publicKeyBase64: String,
        responseBase64: String
    ) async throws -> APITerminalAuthApproveResult {
        lastApproveCall = ApproveCall(
            publicKeyBase64: publicKeyBase64,
            responseBase64: responseBase64
        )
        return approveResult
    }
}

private actor MockDataKeyStore: TerminalDataKeyStoring {
    let dataKey: Data

    init(dataKey: Data) {
        self.dataKey = dataKey
    }

    func loadOrCreateDataKey() async throws -> Data {
        dataKey
    }
}

private final class MockEncryptor: TerminalAuthEncrypting, @unchecked Sendable {
    private(set) var lastMessage: Data?

    func encrypt(message: Data, recipientPublicKeyBase64URL: String) throws -> String {
        lastMessage = message
        return "encrypted-bundle"
    }
}

private func asBase64URL(_ value: Data) -> String {
    value.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
