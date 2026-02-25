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
            initialAppearance: "dark",
            initialExperimentsEnabled: true,
            initialHideInactiveSessions: true,
            initialUseEnhancedSessionWizard: true,
            initialVoiceEnabled: true,
            initialVoiceLanguage: "korean"
        )
        let useCase = SettingsUseCase(store: store)

        let loaded = await useCase.loadSettings()

        #expect(loaded.serverURLString == "https://api.example.com")
        #expect(loaded.apiToken == "token-123")
        #expect(loaded.appLanguage == .korean)
        #expect(loaded.appearance == .dark)
        #expect(loaded.experimentsEnabled == true)
        #expect(loaded.hideInactiveSessions == true)
        #expect(loaded.useEnhancedSessionWizard == true)
        #expect(loaded.voiceEnabled == true)
        #expect(loaded.voiceLanguage == .korean)
    }

    @Test
    func persistSettingsWritesBothValues() async {
        let store = MemoryAppSettingsStore()
        let useCase = SettingsUseCase(store: store)

        await useCase.persistSettings(
            serverURLString: "https://new.example.com",
            apiToken: "next-token",
            appLanguage: .english,
            appearance: .light,
            experimentsEnabled: true,
            hideInactiveSessions: true,
            useEnhancedSessionWizard: false,
            voiceEnabled: true,
            voiceLanguage: .english
        )

        #expect(await store.serverURLString() == "https://new.example.com")
        #expect(await store.apiToken() == "next-token")
        #expect(await store.appLanguageCode() == "english")
        #expect(await store.appearanceMode() == "light")
        #expect(await store.experimentsEnabled() == true)
        #expect(await store.hideInactiveSessions() == true)
        #expect(await store.useEnhancedSessionWizard() == false)
        #expect(await store.voiceEnabled() == true)
        #expect(await store.voiceLanguageCode() == "english")
    }
}

private actor MemoryAppSettingsStore: AppSettingsStore {
    private var savedServerURLString: String
    private var savedAPIToken: String
    private var savedLanguage: String
    private var savedAppearance: String
    private var savedExperimentsEnabled: Bool
    private var savedHideInactiveSessions: Bool
    private var savedUseEnhancedSessionWizard: Bool
    private var savedVoiceEnabled: Bool
    private var savedVoiceLanguage: String

    init(
        initialServerURLString: String = "https://api.unhappy.im",
        initialAPIToken: String = "",
        initialLanguage: String = "system",
        initialAppearance: String = "system",
        initialExperimentsEnabled: Bool = false,
        initialHideInactiveSessions: Bool = false,
        initialUseEnhancedSessionWizard: Bool = false,
        initialVoiceEnabled: Bool = false,
        initialVoiceLanguage: String = "system"
    ) {
        self.savedServerURLString = initialServerURLString
        self.savedAPIToken = initialAPIToken
        self.savedLanguage = initialLanguage
        self.savedAppearance = initialAppearance
        self.savedExperimentsEnabled = initialExperimentsEnabled
        self.savedHideInactiveSessions = initialHideInactiveSessions
        self.savedUseEnhancedSessionWizard = initialUseEnhancedSessionWizard
        self.savedVoiceEnabled = initialVoiceEnabled
        self.savedVoiceLanguage = initialVoiceLanguage
    }

    func serverURLString() async -> String { savedServerURLString }
    func apiToken() async -> String { savedAPIToken }
    func appLanguageCode() async -> String { savedLanguage }
    func appearanceMode() async -> String { savedAppearance }
    func experimentsEnabled() async -> Bool { savedExperimentsEnabled }
    func hideInactiveSessions() async -> Bool { savedHideInactiveSessions }
    func useEnhancedSessionWizard() async -> Bool { savedUseEnhancedSessionWizard }
    func voiceEnabled() async -> Bool { savedVoiceEnabled }
    func voiceLanguageCode() async -> String { savedVoiceLanguage }
    func setServerURLString(_ value: String) async { savedServerURLString = value }
    func setAPIToken(_ value: String) async { savedAPIToken = value }
    func setAppLanguageCode(_ value: String) async { savedLanguage = value }
    func setAppearanceMode(_ value: String) async { savedAppearance = value }
    func setExperimentsEnabled(_ value: Bool) async { savedExperimentsEnabled = value }
    func setHideInactiveSessions(_ value: Bool) async { savedHideInactiveSessions = value }
    func setUseEnhancedSessionWizard(_ value: Bool) async { savedUseEnhancedSessionWizard = value }
    func setVoiceEnabled(_ value: Bool) async { savedVoiceEnabled = value }
    func setVoiceLanguageCode(_ value: String) async { savedVoiceLanguage = value }
}
