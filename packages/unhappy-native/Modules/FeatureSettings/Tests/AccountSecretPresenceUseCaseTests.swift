import Foundation
import Testing
import SecurityKit
@testable import FeatureSettings

struct AccountSecretPresenceUseCaseTests {
    @Test
    func returnsTrueWhenStoreContainsValidSecret() async {
        let store = MemoryAccountSecretStore(secret: Data(repeating: 0x22, count: 32))
        let useCase = AccountSecretPresenceUseCase(store: store)

        let result = await useCase.hasStoredSecret()

        #expect(result == true)
    }

    @Test
    func returnsFalseWhenStoreContainsInvalidSecret() async {
        let store = InvalidAccountSecretStore(raw: "not-a-secret")
        let useCase = AccountSecretPresenceUseCase(store: store)

        let result = await useCase.hasStoredSecret()

        #expect(result == false)
    }
}

private actor MemoryAccountSecretStore: AccountSecretStoring {
    private let raw: String

    init(secret: Data) {
        self.raw = secret.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func loadSecretBase64URL() async -> String {
        raw
    }

    func setSecretBase64URL(_ value: String) async {}
}

private actor InvalidAccountSecretStore: AccountSecretStoring {
    private let raw: String

    init(raw: String) {
        self.raw = raw
    }

    func loadSecretBase64URL() async -> String {
        raw
    }

    func setSecretBase64URL(_ value: String) async {}
}
