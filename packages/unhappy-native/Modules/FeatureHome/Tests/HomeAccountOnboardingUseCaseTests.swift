import Foundation
import Testing
import CoreKit
import FeatureSettings
@testable import FeatureHome

struct HomeAccountOnboardingUseCaseTests {
    @Test
    func createAccountFetchesTokenAndStoresGeneratedSecret() async throws {
        let service = MockAuthTokenService(token: "new-token")
        let secretStore = MockAccountSecretStore()
        let useCase = HomeAccountOnboardingUseCase(
            authTokenService: service,
            secretStore: secretStore
        )

        let token = try await useCase.createAccount(serverURLString: " https://api.unhappy.im ")

        #expect(token == "new-token")
        let call = await service.lastCall
        #expect(call != nil)
        guard let call else { return }
        #expect(call.serverURL.absoluteString == "https://api.unhappy.im")
        #expect(call.secretSeed.count == 32)

        let storedSecret = await secretStore.secretBase64URL
        #expect(!storedSecret.isEmpty)
        #expect(decodeBase64URL(storedSecret) == call.secretSeed)
    }

    @Test
    func createAccountRejectsInvalidServerURL() async {
        let useCase = HomeAccountOnboardingUseCase(
            authTokenService: MockAuthTokenService(),
            secretStore: MockAccountSecretStore()
        )

        await #expect(throws: HomeAccountOnboardingError.invalidServerURL) {
            _ = try await useCase.createAccount(serverURLString: "not a url")
        }
    }

    @Test
    func createAccountMapsAuthTokenAPIErrorToFailedMessage() async {
        let useCase = HomeAccountOnboardingUseCase(
            authTokenService: MockAuthTokenService(error: AuthTokenAPIError.invalidHTTPStatus(401)),
            secretStore: MockAccountSecretStore()
        )

        await #expect(throws: HomeAccountOnboardingError.failed(message: "Request failed with status 401")) {
            _ = try await useCase.createAccount(serverURLString: "https://api.unhappy.im")
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

private actor MockAccountSecretStore: AccountSecretStoring {
    private(set) var secretBase64URL = ""

    func loadSecretBase64URL() async -> String {
        secretBase64URL
    }

    func setSecretBase64URL(_ value: String) async {
        secretBase64URL = value
    }
}

private func decodeBase64URL(_ raw: String) -> Data? {
    var base64 = raw
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let remainder = base64.count % 4
    if remainder != 0 {
        base64.append(String(repeating: "=", count: 4 - remainder))
    }
    return Data(base64Encoded: base64)
}
