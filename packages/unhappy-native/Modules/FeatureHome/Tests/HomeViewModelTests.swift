import Foundation
import Testing
@testable import FeatureHome
import CoreKit

@MainActor
struct HomeViewModelTests {
    @Test
    func initLoadsSettingsFromStore() {
        let store = MemoryAppSettingsStore(
            initialServerURLString: "https://api.example.com",
            initialAPIToken: "token-123"
        )

        let model = HomeViewModel(store: store)

        #expect(model.serverURLString == "https://api.example.com")
        #expect(model.apiToken == "token-123")
    }

    @Test
    func updatesPersistIntoStore() {
        let store = MemoryAppSettingsStore()
        let model = HomeViewModel(store: store)

        model.serverURLString = "https://new.example.com"
        model.apiToken = "next-token"

        #expect(store.savedServerURLString == "https://new.example.com")
        #expect(store.savedAPIToken == "next-token")
    }
}

private final class MemoryAppSettingsStore: AppSettingsStore {
    private(set) var savedServerURLString: String
    private(set) var savedAPIToken: String

    init(
        initialServerURLString: String = "https://api.unhappy.im",
        initialAPIToken: String = ""
    ) {
        self.savedServerURLString = initialServerURLString
        self.savedAPIToken = initialAPIToken
    }

    func serverURLString() -> String { savedServerURLString }
    func apiToken() -> String { savedAPIToken }
    func setServerURLString(_ value: String) { savedServerURLString = value }
    func setAPIToken(_ value: String) { savedAPIToken = value }
}
