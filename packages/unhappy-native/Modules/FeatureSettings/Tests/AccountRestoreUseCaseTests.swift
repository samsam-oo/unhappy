import Foundation
import Testing
import CoreKit
@testable import FeatureSettings

struct AccountRestoreUseCaseTests {
    @Test
    func restoreTokenFetchesTokenUsingDecodedBase64URLSecret() async throws {
        let service = MockAuthTokenService(token: "restored-token")
        let useCase = AccountRestoreUseCase(authTokenService: service)
        let secretSeed = Data(repeating: 0xAB, count: 32)

        let token = try await useCase.restoreToken(
            serverURLString: " https://api.unhappy.im ",
            accountSecretRaw: Base64URLCodec.encode(secretSeed)
        )

        #expect(token == "restored-token")
        let call = await service.lastCall
        #expect(call?.serverURL.absoluteString == "https://api.unhappy.im")
        #expect(call?.secretSeed == secretSeed)
    }

    @Test
    func restoreTokenRejectsMissingSecret() async {
        let useCase = AccountRestoreUseCase(authTokenService: MockAuthTokenService())

        await #expect(throws: AccountRestoreError.missingAccountSecret) {
            _ = try await useCase.restoreToken(
                serverURLString: "https://api.unhappy.im",
                accountSecretRaw: "   "
            )
        }
    }

    @Test
    func restoreTokenRejectsInvalidSecret() async {
        let useCase = AccountRestoreUseCase(authTokenService: MockAuthTokenService())

        await #expect(throws: AccountRestoreError.invalidAccountSecret) {
            _ = try await useCase.restoreToken(
                serverURLString: "https://api.unhappy.im",
                accountSecretRaw: "invalid-secret"
            )
        }
    }

    @Test
    func restoreTokenRejectsInvalidServerURL() async {
        let useCase = AccountRestoreUseCase(authTokenService: MockAuthTokenService())
        let secretSeed = Base64URLCodec.encode(Data(repeating: 0xAB, count: 32))

        await #expect(throws: AccountRestoreError.invalidServerURL) {
            _ = try await useCase.restoreToken(
                serverURLString: "not a url",
                accountSecretRaw: secretSeed
            )
        }
    }

    @Test
    func restoreTokenMapsAuthTokenAPIErrorToFailedMessage() async {
        let useCase = AccountRestoreUseCase(
            authTokenService: MockAuthTokenService(error: AuthTokenAPIError.missingTokenInResponse)
        )
        let secretSeed = Base64URLCodec.encode(Data(repeating: 0xAB, count: 32))

        await #expect(throws: AccountRestoreError.failed(message: "Auth response is missing token")) {
            _ = try await useCase.restoreToken(
                serverURLString: "https://api.unhappy.im",
                accountSecretRaw: secretSeed
            )
        }
    }
}

private actor MockAuthTokenService: AuthTokenFetching {
    struct Call: Equatable {
        let serverURL: URL
        let secretSeed: Data
    }

    private(set) var lastCall: Call?
    private let token: String
    private let error: Error?

    init(token: String = "token", error: Error? = nil) {
        self.token = token
        self.error = error
    }

    func fetchToken(serverURL: URL, secretSeed: Data) async throws -> String {
        if let error {
            throw error
        }
        lastCall = Call(serverURL: serverURL, secretSeed: secretSeed)
        return token
    }
}
