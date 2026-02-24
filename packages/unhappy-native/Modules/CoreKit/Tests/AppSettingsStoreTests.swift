import Foundation
import Testing
@testable import CoreKit

struct AppSettingsStoreTests {
    @Test
    func userDefaultsStoreReturnsDefaultServerWhenMissing() {
        let suiteName = "im.unhappy.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("failed to create UserDefaults test suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsAppSettingsStore(
            defaults: defaults,
            defaultServerURL: "https://default.example.com"
        )

        #expect(store.serverURLString() == "https://default.example.com")
        #expect(store.apiToken() == "")
    }

    @Test
    func userDefaultsStorePersistsServerAndToken() {
        let suiteName = "im.unhappy.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("failed to create UserDefaults test suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        store.setServerURLString("https://api.example.com")
        store.setAPIToken("secret")

        #expect(store.serverURLString() == "https://api.example.com")
        #expect(store.apiToken() == "secret")
    }
}
