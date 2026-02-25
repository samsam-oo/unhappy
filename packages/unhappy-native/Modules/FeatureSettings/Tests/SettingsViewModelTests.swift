import Foundation
import Testing
@testable import FeatureSettings

@MainActor
struct SettingsViewModelTests {
    @Test
    func loadFromStoreAppliesStoredValues() async {
        let settingsManager = MemorySettingsManager(
            initialServerURLString: "https://api.example.com",
            initialAPIToken: "token-123",
            initialLanguage: .korean,
            initialAppearance: .dark
        )
        let model = SettingsViewModel(settingsManager: settingsManager)

        await model.loadFromStore()

        #expect(model.serverURLString == "https://api.example.com")
        #expect(model.apiToken == "token-123")
        #expect(model.selectedLanguage == .korean)
        #expect(model.selectedAppearance == .dark)
    }

    @Test
    func updatesPersistIntoSettingsManager() async {
        let settingsManager = MemorySettingsManager()
        let model = SettingsViewModel(settingsManager: settingsManager)
        await model.loadFromStore()

        model.serverURLString = "https://new.example.com"
        model.apiToken = "next-token"
        model.selectedLanguage = .english
        model.selectedAppearance = .light
        await model.waitForPendingPersistence()

        let persisted = await settingsManager.loadSettings()
        #expect(persisted.serverURLString == "https://new.example.com")
        #expect(persisted.apiToken == "next-token")
        #expect(persisted.appLanguage == .english)
        #expect(persisted.appearance == .light)
    }
}

private actor MemorySettingsManager: SettingsManaging {
    private var savedServerURLString: String
    private var savedAPIToken: String
    private var savedLanguage: AppLanguageOption
    private var savedAppearance: AppAppearanceOption

    init(
        initialServerURLString: String = "https://api.unhappy.im",
        initialAPIToken: String = "",
        initialLanguage: AppLanguageOption = .system,
        initialAppearance: AppAppearanceOption = .system
    ) {
        self.savedServerURLString = initialServerURLString
        self.savedAPIToken = initialAPIToken
        self.savedLanguage = initialLanguage
        self.savedAppearance = initialAppearance
    }

    func loadSettings() async -> AppSettingsSnapshot {
        AppSettingsSnapshot(
            serverURLString: savedServerURLString,
            apiToken: savedAPIToken,
            appLanguage: savedLanguage,
            appearance: savedAppearance
        )
    }

    func persistSettings(
        serverURLString: String,
        apiToken: String,
        appLanguage: AppLanguageOption,
        appearance: AppAppearanceOption
    ) async {
        savedServerURLString = serverURLString
        savedAPIToken = apiToken
        savedLanguage = appLanguage
        savedAppearance = appearance
    }
}
