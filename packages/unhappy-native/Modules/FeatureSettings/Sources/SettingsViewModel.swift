import Foundation
import CoreKit

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var serverURLString: String {
        didSet {
            guard hasLoadedInitialSettings else { return }
            schedulePersistence()
        }
    }

    @Published public var apiToken: String {
        didSet {
            guard hasLoadedInitialSettings else { return }
            schedulePersistence()
        }
    }
    @Published public var selectedLanguage: AppLanguageOption {
        didSet {
            guard hasLoadedInitialSettings else { return }
            schedulePersistence()
        }
    }
    @Published public var selectedAppearance: AppAppearanceOption {
        didSet {
            guard hasLoadedInitialSettings else { return }
            schedulePersistence()
        }
    }
    @Published public var experimentsEnabled: Bool {
        didSet {
            guard hasLoadedInitialSettings else { return }
            schedulePersistence()
        }
    }
    @Published public var hideInactiveSessions: Bool {
        didSet {
            guard hasLoadedInitialSettings else { return }
            schedulePersistence()
        }
    }
    @Published public var useEnhancedSessionWizard: Bool {
        didSet {
            guard hasLoadedInitialSettings else { return }
            schedulePersistence()
        }
    }
    @Published public var voiceEnabled: Bool {
        didSet {
            guard hasLoadedInitialSettings else { return }
            schedulePersistence()
        }
    }
    @Published public var voiceLanguage: AppVoiceLanguageOption {
        didSet {
            guard hasLoadedInitialSettings else { return }
            schedulePersistence()
        }
    }
    @Published public var defaultNewSessionAgent: APISessionSpawnAgent {
        didSet {
            guard hasLoadedInitialSettings else { return }
            schedulePersistence()
        }
    }
    @Published public var lastViewedChangelogID: String {
        didSet {
            refreshUnreadChangelogState()
            guard hasLoadedInitialSettings else { return }
            schedulePersistence()
        }
    }
    @Published public private(set) var hasUnreadChangelog: Bool

    private let settingsManager: any SettingsManaging
    private var hasLoadedInitialSettings = false
    private var persistenceTask: Task<Void, Never>?

    public init(settingsManager: any SettingsManaging) {
        self.settingsManager = settingsManager
        self.serverURLString = "https://api.unhappy.im"
        self.apiToken = ""
        self.selectedLanguage = .system
        self.selectedAppearance = .system
        self.experimentsEnabled = false
        self.hideInactiveSessions = false
        self.useEnhancedSessionWizard = false
        self.voiceEnabled = false
        self.voiceLanguage = .system
        self.defaultNewSessionAgent = .claude
        self.lastViewedChangelogID = ""
        self.hasUnreadChangelog = SettingsChangelog.hasUnread(lastViewedID: "")
    }

    deinit {
        persistenceTask?.cancel()
    }

    public func loadFromStore() async {
        hasLoadedInitialSettings = false
        let settings = await settingsManager.loadSettings()
        serverURLString = settings.serverURLString
        apiToken = settings.apiToken
        selectedLanguage = settings.appLanguage
        selectedAppearance = settings.appearance
        experimentsEnabled = settings.experimentsEnabled
        hideInactiveSessions = settings.hideInactiveSessions
        useEnhancedSessionWizard = settings.useEnhancedSessionWizard
        voiceEnabled = settings.voiceEnabled
        voiceLanguage = settings.voiceLanguage
        defaultNewSessionAgent = settings.defaultNewSessionAgent
        lastViewedChangelogID = settings.lastViewedChangelogID
        refreshUnreadChangelogState()
        hasLoadedInitialSettings = true
    }

    public func markLatestChangelogViewed() {
        let latestID = SettingsChangelog.latestEntryID
        guard !latestID.isEmpty, lastViewedChangelogID != latestID else { return }
        lastViewedChangelogID = latestID
    }

    func waitForPendingPersistence() async {
        await persistenceTask?.value
    }

    private func schedulePersistence() {
        let manager = settingsManager
        let snapshot = AppSettingsSnapshot(
            serverURLString: serverURLString,
            apiToken: apiToken,
            appLanguage: selectedLanguage,
            appearance: selectedAppearance,
            experimentsEnabled: experimentsEnabled,
            hideInactiveSessions: hideInactiveSessions,
            useEnhancedSessionWizard: useEnhancedSessionWizard,
            voiceEnabled: voiceEnabled,
            voiceLanguage: voiceLanguage,
            defaultNewSessionAgent: defaultNewSessionAgent,
            lastViewedChangelogID: lastViewedChangelogID
        )
        persistenceTask?.cancel()
        persistenceTask = Task {
            guard !Task.isCancelled else { return }
            await manager.persistSettings(snapshot)
        }
    }

    private func refreshUnreadChangelogState() {
        hasUnreadChangelog = SettingsChangelog.hasUnread(lastViewedID: lastViewedChangelogID)
    }
}
