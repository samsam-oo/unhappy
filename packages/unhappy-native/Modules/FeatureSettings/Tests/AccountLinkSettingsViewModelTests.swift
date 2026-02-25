import Foundation
import Testing
@testable import FeatureSettings

@MainActor
struct AccountLinkSettingsViewModelTests {
    @Test
    func loadFromStoreHydratesSecret() async {
        let secretStore = MemoryAccountSecretStore(initialSecret: "secret-base64url")
        let model = AccountLinkSettingsViewModel(
            linker: MockAccountLinker(),
            restorer: MockAccountRestorer(),
            secretStore: secretStore
        )

        await model.loadFromStore()

        #expect(model.accountSecretBase64URL == "secret-base64url")
    }

    @Test
    func changingSecretPersistsToStore() async {
        let secretStore = MemoryAccountSecretStore(initialSecret: "")
        let model = AccountLinkSettingsViewModel(
            linker: MockAccountLinker(),
            restorer: MockAccountRestorer(),
            secretStore: secretStore
        )

        await model.loadFromStore()
        model.accountSecretBase64URL = " next-secret "
        try? await Task.sleep(nanoseconds: 20_000_000)

        #expect(await secretStore.loadSecretBase64URL() == "next-secret")
    }

    @Test
    func linkDeviceSetsSuccessMessage() async {
        let linker = MockAccountLinker()
        let model = AccountLinkSettingsViewModel(
            linker: linker,
            restorer: MockAccountRestorer(),
            secretStore: MemoryAccountSecretStore(initialSecret: "secret")
        )

        await model.loadFromStore()
        await model.linkDevice(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            accountAuthURLString: "unhappy://account?abc123"
        )

        #expect(model.statusMessage == "Device linked successfully")
        #expect(model.errorMessage == nil)
        #expect(model.isLinking == false)
        #expect(await linker.lastCall?.serverURLString == "https://api.unhappy.im")
    }

    @Test
    func linkDeviceSetsErrorMessage() async {
        let linker = MockAccountLinker(error: AccountLinkError.invalidAccountAuthURL)
        let model = AccountLinkSettingsViewModel(
            linker: linker,
            restorer: MockAccountRestorer(),
            secretStore: MemoryAccountSecretStore(initialSecret: "secret")
        )

        await model.loadFromStore()
        await model.linkDevice(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            accountAuthURLString: "invalid"
        )

        #expect(model.statusMessage == nil)
        #expect(model.errorMessage == "Invalid account QR URL")
        #expect(model.isLinking == false)
    }

    @Test
    func restoreTokenSetsSuccessMessageAndReturnsToken() async {
        let restorer = MockAccountRestorer(token: "restored-token")
        let model = AccountLinkSettingsViewModel(
            linker: MockAccountLinker(),
            restorer: restorer,
            secretStore: MemoryAccountSecretStore(initialSecret: "secret")
        )

        await model.loadFromStore()
        let token = await model.restoreToken(serverURLString: "https://api.unhappy.im")

        #expect(token == "restored-token")
        #expect(model.statusMessage == "Recovered API token from secret key")
        #expect(model.errorMessage == nil)
        #expect(model.isRestoring == false)
        #expect(await restorer.lastCall?.serverURLString == "https://api.unhappy.im")
    }

    @Test
    func restoreTokenSetsErrorMessage() async {
        let restorer = MockAccountRestorer(error: AccountRestoreError.invalidAccountSecret)
        let model = AccountLinkSettingsViewModel(
            linker: MockAccountLinker(),
            restorer: restorer,
            secretStore: MemoryAccountSecretStore(initialSecret: "secret")
        )

        await model.loadFromStore()
        let token = await model.restoreToken(serverURLString: "https://api.unhappy.im")

        #expect(token == nil)
        #expect(model.statusMessage == nil)
        #expect(model.errorMessage == "Invalid account secret key")
        #expect(model.isRestoring == false)
    }
}

private actor MemoryAccountSecretStore: AccountSecretStoring {
    private var savedSecret: String

    init(initialSecret: String) {
        self.savedSecret = initialSecret
    }

    func loadSecretBase64URL() async -> String {
        savedSecret
    }

    func setSecretBase64URL(_ value: String) async {
        savedSecret = value
    }
}

private actor MockAccountLinker: AccountLinkingAction {
    struct LinkCall: Equatable {
        let serverURLString: String
        let token: String
        let accountSecretBase64URL: String
        let accountAuthURLString: String
    }

    private(set) var lastCall: LinkCall?
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func approveAccountLink(
        serverURLString: String,
        token: String,
        accountSecretBase64URL: String,
        accountAuthURLString: String
    ) async throws {
        if let error {
            throw error
        }
        lastCall = LinkCall(
            serverURLString: serverURLString,
            token: token,
            accountSecretBase64URL: accountSecretBase64URL,
            accountAuthURLString: accountAuthURLString
        )
    }
}

private actor MockAccountRestorer: AccountTokenRestoringAction {
    struct RestoreCall: Equatable {
        let serverURLString: String
        let accountSecretRaw: String
    }

    private(set) var lastCall: RestoreCall?
    private let token: String
    private let error: Error?

    init(token: String = "token", error: Error? = nil) {
        self.token = token
        self.error = error
    }

    func restoreToken(serverURLString: String, accountSecretRaw: String) async throws -> String {
        if let error {
            throw error
        }
        lastCall = RestoreCall(
            serverURLString: serverURLString,
            accountSecretRaw: accountSecretRaw
        )
        return token
    }
}
