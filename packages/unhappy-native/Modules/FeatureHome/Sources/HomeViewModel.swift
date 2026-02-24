import Foundation
import FeatureSettings

@MainActor
public final class HomeViewModel: ObservableObject {
    @Published public var serverURLString: String {
        didSet {
            guard hasLoadedInitialSettings else { return }
            scheduleSettingsPersistence()
        }
    }

    @Published public var apiToken: String {
        didSet {
            guard hasLoadedInitialSettings else { return }
            scheduleSettingsPersistence()
        }
    }

    private let settingsManager: any SettingsManaging
    private var hasLoadedInitialSettings = false
    private var settingsPersistenceTask: Task<Void, Never>?

    public init(settingsManager: any SettingsManaging) {
        self.settingsManager = settingsManager
        self.serverURLString = "https://api.unhappy.im"
        self.apiToken = ""
    }

    deinit {
        settingsPersistenceTask?.cancel()
    }

    public func loadFromStore() async {
        hasLoadedInitialSettings = false
        let settings = await settingsManager.loadSettings()
        serverURLString = settings.serverURLString
        apiToken = settings.apiToken
        hasLoadedInitialSettings = true
    }

    func waitForPendingPersistence() async {
        await settingsPersistenceTask?.value
    }

    private func scheduleSettingsPersistence() {
        let manager = settingsManager
        let serverURLString = self.serverURLString
        let apiToken = self.apiToken
        settingsPersistenceTask?.cancel()
        settingsPersistenceTask = Task {
            guard !Task.isCancelled else { return }
            await manager.persistSettings(
                serverURLString: serverURLString,
                apiToken: apiToken
            )
        }
    }
}
