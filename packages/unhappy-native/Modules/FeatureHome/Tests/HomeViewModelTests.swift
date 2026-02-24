import Foundation
import Testing
@testable import FeatureHome
import FeatureSettings

@MainActor
struct HomeViewModelTests {
    @Test
    func loadFromStoreAppliesStoredValues() async {
        let settingsManager = MemorySettingsManager(
            initialServerURLString: "https://api.example.com",
            initialAPIToken: "token-123"
        )

        let model = HomeViewModel(settingsManager: settingsManager)
        await model.loadFromStore()

        #expect(model.serverURLString == "https://api.example.com")
        #expect(model.apiToken == "token-123")
    }

    @Test
    func updatesPersistIntoStore() async {
        let settingsManager = MemorySettingsManager()
        let model = HomeViewModel(settingsManager: settingsManager)
        await model.loadFromStore()

        model.serverURLString = "https://new.example.com"
        model.apiToken = "next-token"
        await model.waitForPendingPersistence()

        let persisted = await settingsManager.loadSettings()
        #expect(persisted.serverURLString == "https://new.example.com")
        #expect(persisted.apiToken == "next-token")
    }
}

private actor MemorySettingsManager: SettingsManaging {
    private var savedServerURLString: String
    private var savedAPIToken: String

    init(
        initialServerURLString: String = "https://api.unhappy.im",
        initialAPIToken: String = ""
    ) {
        self.savedServerURLString = initialServerURLString
        self.savedAPIToken = initialAPIToken
    }

    func loadSettings() async -> AppSettingsSnapshot {
        AppSettingsSnapshot(
            serverURLString: savedServerURLString,
            apiToken: savedAPIToken
        )
    }

    func persistSettings(serverURLString: String, apiToken: String) async {
        savedServerURLString = serverURLString
        savedAPIToken = apiToken
    }
}
