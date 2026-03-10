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
            qrRestorer: MockAccountQRRestorer(),
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
            qrRestorer: MockAccountQRRestorer(),
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
            qrRestorer: MockAccountQRRestorer(),
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
            qrRestorer: MockAccountQRRestorer(),
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
        let secretStore = MemoryAccountSecretStore(initialSecret: "secret")
        let model = AccountLinkSettingsViewModel(
            linker: MockAccountLinker(),
            restorer: restorer,
            qrRestorer: MockAccountQRRestorer(),
            secretStore: secretStore
        )

        await model.loadFromStore()
        let token = await model.restoreToken(serverURLString: "https://api.unhappy.im")

        #expect(token == "restored-token")
        #expect(model.statusMessage == "Recovered API token from secret key")
        #expect(model.errorMessage == nil)
        #expect(model.isRestoring == false)
        #expect(await restorer.lastCall?.serverURLString == "https://api.unhappy.im")
        #expect(await secretStore.loadSecretBase64URL() == "secret")
    }

    @Test
    func restoreTokenPersistsEditedSecretBeforeReturningToken() async {
        let secretStore = MemoryAccountSecretStore(initialSecret: "")
        let restorer = MockAccountRestorer(token: "restored-token")
        let model = AccountLinkSettingsViewModel(
            linker: MockAccountLinker(),
            restorer: restorer,
            qrRestorer: MockAccountQRRestorer(),
            secretStore: secretStore
        )

        await model.loadFromStore()
        model.accountSecretBase64URL = " edited-secret "
        let token = await model.restoreToken(serverURLString: "https://api.unhappy.im")

        #expect(token == "restored-token")
        #expect(await secretStore.loadSecretBase64URL() == "edited-secret")
    }

    @Test
    func restoreTokenSetsErrorMessage() async {
        let restorer = MockAccountRestorer(error: AccountRestoreError.invalidAccountSecret)
        let model = AccountLinkSettingsViewModel(
            linker: MockAccountLinker(),
            restorer: restorer,
            qrRestorer: MockAccountQRRestorer(),
            secretStore: MemoryAccountSecretStore(initialSecret: "secret")
        )

        await model.loadFromStore()
        let token = await model.restoreToken(serverURLString: "https://api.unhappy.im")

        #expect(token == nil)
        #expect(model.statusMessage == nil)
        #expect(model.errorMessage == "Invalid account secret key")
        #expect(model.isRestoring == false)
    }

    @Test
    func restoreTokenFromQRCodeSetsSecretAndReturnsToken() async {
        let qrRestorer = MockAccountQRRestorer(
            pollResults: [
                .authorized(AccountRestoreQRCredentials(token: "qr-token", secretBase64URL: "qr-secret"))
            ]
        )
        let secretStore = MemoryAccountSecretStore(initialSecret: "secret")
        let model = AccountLinkSettingsViewModel(
            linker: MockAccountLinker(),
            restorer: MockAccountRestorer(),
            qrRestorer: qrRestorer,
            secretStore: secretStore
        )

        await model.loadFromStore()
        let token = await model.restoreTokenFromQRCode(serverURLString: "https://api.unhappy.im")

        #expect(token == "qr-token")
        #expect(model.accountSecretBase64URL == "qr-secret")
        #expect(model.statusMessage == "Recovered API token from QR approval")
        #expect(model.errorMessage == nil)
        #expect(model.isRestoringByQR == false)
        #expect(await qrRestorer.pollCallCount == 1)
        #expect(await secretStore.loadSecretBase64URL() == "qr-secret")
    }

    @Test
    func restoreTokenFromQRCodeSetsErrorMessage() async {
        let qrRestorer = MockAccountQRRestorer(error: AccountRestoreQRError.missingTokenInResponse)
        let model = AccountLinkSettingsViewModel(
            linker: MockAccountLinker(),
            restorer: MockAccountRestorer(),
            qrRestorer: qrRestorer,
            secretStore: MemoryAccountSecretStore(initialSecret: "secret")
        )

        await model.loadFromStore()
        let token = await model.restoreTokenFromQRCode(serverURLString: "https://api.unhappy.im")

        #expect(token == nil)
        #expect(model.statusMessage == nil)
        #expect(model.errorMessage == "Auth response is missing encrypted token")
        #expect(model.isRestoringByQR == false)
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

private actor MockAccountQRRestorer: AccountQRRestoringAction {
    private(set) var pollCallCount = 0
    private let pollResults: [AccountRestoreQRPollResult]
    private let error: Error?

    init(
        pollResults: [AccountRestoreQRPollResult] = [.pending],
        error: Error? = nil
    ) {
        self.pollResults = pollResults
        self.error = error
    }

    func createSession() async throws -> AccountRestoreQRSession {
        AccountRestoreQRSession(
            publicKeyBase64: "public-key",
            secretKey: Data(repeating: 1, count: 32),
            qrPayload: "unhappy:///account?abc123"
        )
    }

    func pollStatus(
        serverURLString: String,
        session: AccountRestoreQRSession
    ) async throws -> AccountRestoreQRPollResult {
        if let error {
            throw error
        }
        pollCallCount += 1
        let index = min(pollCallCount - 1, pollResults.count - 1)
        return pollResults[index]
    }
}
