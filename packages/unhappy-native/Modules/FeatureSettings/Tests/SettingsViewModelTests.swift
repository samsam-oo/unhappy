import Foundation
import Testing
@testable import FeatureSettings
import CoreKit

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
            initialVoiceLanguage: .korean,
            initialDefaultNewSessionAgent: .codex,
            initialLastViewedChangelogID: "2026.02.21"
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
        #expect(model.defaultNewSessionAgent == .codex)
        #expect(model.lastViewedChangelogID == "2026.02.21")
        #expect(model.hasUnreadChangelog == true)
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
        model.defaultNewSessionAgent = .gemini
        model.lastViewedChangelogID = "2026.02.14"
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
        #expect(persisted.defaultNewSessionAgent == .gemini)
        #expect(persisted.lastViewedChangelogID == "2026.02.14")
    }

    @Test
    func markLatestChangelogViewedClearsUnreadAndPersists() async {
        let settingsManager = MemorySettingsManager(
            initialLastViewedChangelogID: "2026.02.14"
        )
        let model = SettingsViewModel(settingsManager: settingsManager)
        await model.loadFromStore()

        #expect(model.hasUnreadChangelog == true)

        model.markLatestChangelogViewed()
        await model.waitForPendingPersistence()

        #expect(model.lastViewedChangelogID == SettingsChangelog.latestEntryID)
        #expect(model.hasUnreadChangelog == false)

        let persisted = await settingsManager.loadSettings()
        #expect(persisted.lastViewedChangelogID == SettingsChangelog.latestEntryID)
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
    private var savedDefaultNewSessionAgent: APISessionSpawnAgent
    private var savedLastViewedChangelogID: String

    init(
        initialServerURLString: String = "https://api.unhappy.im",
        initialAPIToken: String = "",
        initialLanguage: AppLanguageOption = .system,
        initialAppearance: AppAppearanceOption = .system,
        initialExperimentsEnabled: Bool = false,
        initialHideInactiveSessions: Bool = false,
        initialUseEnhancedSessionWizard: Bool = false,
        initialVoiceEnabled: Bool = false,
        initialVoiceLanguage: AppVoiceLanguageOption = .system,
        initialDefaultNewSessionAgent: APISessionSpawnAgent = .claude,
        initialLastViewedChangelogID: String = ""
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
        self.savedDefaultNewSessionAgent = initialDefaultNewSessionAgent
        self.savedLastViewedChangelogID = initialLastViewedChangelogID
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
            voiceLanguage: savedVoiceLanguage,
            defaultNewSessionAgent: savedDefaultNewSessionAgent,
            lastViewedChangelogID: savedLastViewedChangelogID
        )
    }

    func persistSettings(_ snapshot: AppSettingsSnapshot) async {
        savedServerURLString = snapshot.serverURLString
        savedAPIToken = snapshot.apiToken
        savedLanguage = snapshot.appLanguage
        savedAppearance = snapshot.appearance
        savedExperimentsEnabled = snapshot.experimentsEnabled
        savedHideInactiveSessions = snapshot.hideInactiveSessions
        savedUseEnhancedSessionWizard = snapshot.useEnhancedSessionWizard
        savedVoiceEnabled = snapshot.voiceEnabled
        savedVoiceLanguage = snapshot.voiceLanguage
        savedDefaultNewSessionAgent = snapshot.defaultNewSessionAgent
        savedLastViewedChangelogID = snapshot.lastViewedChangelogID
    }
}
