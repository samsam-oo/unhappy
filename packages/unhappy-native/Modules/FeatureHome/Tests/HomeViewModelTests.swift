import Foundation
import Testing
@testable import FeatureHome
import CoreKit

@MainActor
struct HomeViewModelTests {
    @Test
    func loadFromStoreAppliesStoredValues() async {
        let store = MemoryAppSettingsStore(
            initialServerURLString: "https://api.example.com",
            initialAPIToken: "token-123"
        )

        let model = HomeViewModel(store: store)
        await model.loadFromStore()

        #expect(model.serverURLString == "https://api.example.com")
        #expect(model.apiToken == "token-123")
    }

    @Test
    func updatesPersistIntoStore() async {
        let store = MemoryAppSettingsStore()
        let model = HomeViewModel(store: store)
        await model.loadFromStore()

        model.serverURLString = "https://new.example.com"
        model.apiToken = "next-token"
        await model.waitForPendingPersistence()

        #expect(await store.serverURLString() == "https://new.example.com")
        #expect(await store.apiToken() == "next-token")
    }
}

private actor MemoryAppSettingsStore: AppSettingsStore {
    private var savedServerURLString: String
    private var savedAPIToken: String

    init(
        initialServerURLString: String = "https://api.unhappy.im",
        initialAPIToken: String = ""
    ) {
        self.savedServerURLString = initialServerURLString
        self.savedAPIToken = initialAPIToken
    }

    func serverURLString() async -> String { savedServerURLString }
    func apiToken() async -> String { savedAPIToken }
    func setServerURLString(_ value: String) async { savedServerURLString = value }
    func setAPIToken(_ value: String) async { savedAPIToken = value }
}
