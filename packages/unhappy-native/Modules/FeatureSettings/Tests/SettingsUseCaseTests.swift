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
            initialVoiceLanguage: "korean",
            initialDefaultAgent: "codex",
            initialLastViewedChangelogID: "2026.02.21"
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
        #expect(loaded.defaultNewSessionAgent == .codex)
        #expect(loaded.lastViewedChangelogID == "2026.02.21")
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
            voiceLanguage: .english,
            defaultNewSessionAgent: .gemini,
            lastViewedChangelogID: "2026.02.26"
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
        #expect(await store.defaultNewSessionAgent() == "gemini")
        #expect(await store.lastViewedChangelogID() == "2026.02.26")
    }

    @Test
    func changelogUnreadStateTransitionsAfterPersistingLatest() async {
        let store = MemoryAppSettingsStore(
            initialLastViewedChangelogID: "2026.02.21"
        )
        let useCase = SettingsUseCase(store: store)

        let loadedBefore = await useCase.loadSettings()
        #expect(SettingsChangelog.hasUnread(lastViewedID: loadedBefore.lastViewedChangelogID))

        await useCase.persistSettings(
            serverURLString: loadedBefore.serverURLString,
            apiToken: loadedBefore.apiToken,
            appLanguage: loadedBefore.appLanguage,
            appearance: loadedBefore.appearance,
            experimentsEnabled: loadedBefore.experimentsEnabled,
            hideInactiveSessions: loadedBefore.hideInactiveSessions,
            useEnhancedSessionWizard: loadedBefore.useEnhancedSessionWizard,
            voiceEnabled: loadedBefore.voiceEnabled,
            voiceLanguage: loadedBefore.voiceLanguage,
            defaultNewSessionAgent: loadedBefore.defaultNewSessionAgent,
            lastViewedChangelogID: SettingsChangelog.latestEntryID
        )

        let loadedAfter = await useCase.loadSettings()
        #expect(loadedAfter.lastViewedChangelogID == SettingsChangelog.latestEntryID)
        #expect(!SettingsChangelog.hasUnread(lastViewedID: loadedAfter.lastViewedChangelogID))
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
    private var savedDefaultAgent: String
    private var savedLastViewedChangelogID: String
    private var savedRecentProjects: [String]

    init(
        initialServerURLString: String = "https://api.unhappy.im",
        initialAPIToken: String = "",
        initialLanguage: String = "system",
        initialAppearance: String = "system",
        initialExperimentsEnabled: Bool = false,
        initialHideInactiveSessions: Bool = false,
        initialUseEnhancedSessionWizard: Bool = false,
        initialVoiceEnabled: Bool = false,
        initialVoiceLanguage: String = "system",
        initialDefaultAgent: String = "claude",
        initialLastViewedChangelogID: String = "",
        initialRecentProjects: [String] = []
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
        self.savedDefaultAgent = initialDefaultAgent
        self.savedLastViewedChangelogID = initialLastViewedChangelogID
        self.savedRecentProjects = initialRecentProjects
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
    func defaultNewSessionAgent() async -> String { savedDefaultAgent }
    func lastViewedChangelogID() async -> String { savedLastViewedChangelogID }
    func recentProjectPaths() async -> [String] { savedRecentProjects }
    func setServerURLString(_ value: String) async { savedServerURLString = value }
    func setAPIToken(_ value: String) async { savedAPIToken = value }
    func setAppLanguageCode(_ value: String) async { savedLanguage = value }
    func setAppearanceMode(_ value: String) async { savedAppearance = value }
    func setExperimentsEnabled(_ value: Bool) async { savedExperimentsEnabled = value }
    func setHideInactiveSessions(_ value: Bool) async { savedHideInactiveSessions = value }
    func setUseEnhancedSessionWizard(_ value: Bool) async { savedUseEnhancedSessionWizard = value }
    func setVoiceEnabled(_ value: Bool) async { savedVoiceEnabled = value }
    func setVoiceLanguageCode(_ value: String) async { savedVoiceLanguage = value }
    func setDefaultNewSessionAgent(_ value: String) async { savedDefaultAgent = value }
    func setLastViewedChangelogID(_ value: String) async { savedLastViewedChangelogID = value }
    func setRecentProjectPaths(_ value: [String]) async { savedRecentProjects = value }
}
