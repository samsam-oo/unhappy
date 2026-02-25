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
            initialAppearance: .dark,
            initialExperimentsEnabled: true,
            initialHideInactiveSessions: true,
            initialUseEnhancedSessionWizard: true,
            initialVoiceEnabled: true,
            initialVoiceLanguage: .korean
        )
        let model = SettingsViewModel(settingsManager: settingsManager)

        await model.loadFromStore()

        #expect(model.serverURLString == "https://api.example.com")
        #expect(model.apiToken == "token-123")
        #expect(model.selectedLanguage == .korean)
        #expect(model.selectedAppearance == .dark)
        #expect(model.experimentsEnabled == true)
        #expect(model.hideInactiveSessions == true)
        #expect(model.useEnhancedSessionWizard == true)
        #expect(model.voiceEnabled == true)
        #expect(model.voiceLanguage == .korean)
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
        model.experimentsEnabled = true
        model.hideInactiveSessions = true
        model.useEnhancedSessionWizard = false
        model.voiceEnabled = true
        model.voiceLanguage = .english
        await model.waitForPendingPersistence()

        let persisted = await settingsManager.loadSettings()
        #expect(persisted.serverURLString == "https://new.example.com")
        #expect(persisted.apiToken == "next-token")
        #expect(persisted.appLanguage == .english)
        #expect(persisted.appearance == .light)
        #expect(persisted.experimentsEnabled == true)
        #expect(persisted.hideInactiveSessions == true)
        #expect(persisted.useEnhancedSessionWizard == false)
        #expect(persisted.voiceEnabled == true)
        #expect(persisted.voiceLanguage == .english)
    }
}

private actor MemorySettingsManager: SettingsManaging {
    private var savedServerURLString: String
    private var savedAPIToken: String
    private var savedLanguage: AppLanguageOption
    private var savedAppearance: AppAppearanceOption
    private var savedExperimentsEnabled: Bool
    private var savedHideInactiveSessions: Bool
    private var savedUseEnhancedSessionWizard: Bool
    private var savedVoiceEnabled: Bool
    private var savedVoiceLanguage: AppVoiceLanguageOption

    init(
        initialServerURLString: String = "https://api.unhappy.im",
        initialAPIToken: String = "",
        initialLanguage: AppLanguageOption = .system,
        initialAppearance: AppAppearanceOption = .system,
        initialExperimentsEnabled: Bool = false,
        initialHideInactiveSessions: Bool = false,
        initialUseEnhancedSessionWizard: Bool = false,
        initialVoiceEnabled: Bool = false,
        initialVoiceLanguage: AppVoiceLanguageOption = .system
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

    func loadSettings() async -> AppSettingsSnapshot {
        AppSettingsSnapshot(
            serverURLString: savedServerURLString,
            apiToken: savedAPIToken,
            appLanguage: savedLanguage,
            appearance: savedAppearance,
            experimentsEnabled: savedExperimentsEnabled,
            hideInactiveSessions: savedHideInactiveSessions,
            useEnhancedSessionWizard: savedUseEnhancedSessionWizard,
            voiceEnabled: savedVoiceEnabled,
            voiceLanguage: savedVoiceLanguage
        )
    }

    func persistSettings(
        serverURLString: String,
        apiToken: String,
        appLanguage: AppLanguageOption,
        appearance: AppAppearanceOption,
        experimentsEnabled: Bool,
        hideInactiveSessions: Bool,
        useEnhancedSessionWizard: Bool,
        voiceEnabled: Bool,
        voiceLanguage: AppVoiceLanguageOption
    ) async {
        savedServerURLString = serverURLString
        savedAPIToken = apiToken
        savedLanguage = appLanguage
        savedAppearance = appearance
        savedExperimentsEnabled = experimentsEnabled
        savedHideInactiveSessions = hideInactiveSessions
        savedUseEnhancedSessionWizard = useEnhancedSessionWizard
        savedVoiceEnabled = voiceEnabled
        savedVoiceLanguage = voiceLanguage
    }
}
