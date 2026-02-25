import Foundation

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

    private let settingsManager: any SettingsManaging
    private var hasLoadedInitialSettings = false
    private var persistenceTask: Task<Void, Never>?

    public init(settingsManager: any SettingsManaging) {
        self.settingsManager = settingsManager
        self.serverURLString = "https://api.unhappy.im"
        self.apiToken = ""
        self.selectedLanguage = .system
        self.selectedAppearance = .system
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
        hasLoadedInitialSettings = true
    }

    func waitForPendingPersistence() async {
        await persistenceTask?.value
    }

    private func schedulePersistence() {
        let manager = settingsManager
        let serverURLString = self.serverURLString
        let apiToken = self.apiToken
        let selectedLanguage = self.selectedLanguage
        let selectedAppearance = self.selectedAppearance
        persistenceTask?.cancel()
        persistenceTask = Task {
            guard !Task.isCancelled else { return }
            await manager.persistSettings(
                serverURLString: serverURLString,
                apiToken: apiToken,
                appLanguage: selectedLanguage,
                appearance: selectedAppearance
            )
        }
    }
}
