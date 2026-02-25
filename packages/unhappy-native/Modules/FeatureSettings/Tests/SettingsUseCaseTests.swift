import Foundation
import Testing
@testable import FeatureSettings
import CoreKit

struct SettingsUseCaseTests {
    @Test
    func loadSettingsReturnsValuesFromStore() async {
        let store = MemoryAppSettingsStore(
            initialServerURLString: "https://api.example.com",
            initialAPIToken: "token-123",
            initialLanguage: "korean",
            initialAppearance: "dark"
        )
        let useCase = SettingsUseCase(store: store)

        let loaded = await useCase.loadSettings()

        #expect(loaded.serverURLString == "https://api.example.com")
        #expect(loaded.apiToken == "token-123")
        #expect(loaded.appLanguage == .korean)
        #expect(loaded.appearance == .dark)
    }

    @Test
    func persistSettingsWritesBothValues() async {
        let store = MemoryAppSettingsStore()
        let useCase = SettingsUseCase(store: store)

        await useCase.persistSettings(
            serverURLString: "https://new.example.com",
            apiToken: "next-token",
            appLanguage: .english,
            appearance: .light
        )

        #expect(await store.serverURLString() == "https://new.example.com")
        #expect(await store.apiToken() == "next-token")
        #expect(await store.appLanguageCode() == "english")
        #expect(await store.appearanceMode() == "light")
    }
}

private actor MemoryAppSettingsStore: AppSettingsStore {
    private var savedServerURLString: String
    private var savedAPIToken: String
    private var savedLanguage: String
    private var savedAppearance: String

    init(
        initialServerURLString: String = "https://api.unhappy.im",
        initialAPIToken: String = "",
        initialLanguage: String = "system",
        initialAppearance: String = "system"
    ) {
        self.savedServerURLString = initialServerURLString
        self.savedAPIToken = initialAPIToken
        self.savedLanguage = initialLanguage
        self.savedAppearance = initialAppearance
    }

    func serverURLString() async -> String { savedServerURLString }
    func apiToken() async -> String { savedAPIToken }
    func appLanguageCode() async -> String { savedLanguage }
    func appearanceMode() async -> String { savedAppearance }
    func setServerURLString(_ value: String) async { savedServerURLString = value }
    func setAPIToken(_ value: String) async { savedAPIToken = value }
    func setAppLanguageCode(_ value: String) async { savedLanguage = value }
    func setAppearanceMode(_ value: String) async { savedAppearance = value }
}
