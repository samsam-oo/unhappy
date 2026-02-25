import Foundation
import Testing
@testable import CoreKit

struct AppSettingsStoreTests {
    @Test
    func userDefaultsStoreReturnsDefaultServerWhenMissing() async {
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

        #expect(await store.serverURLString() == "https://default.example.com")
        #expect(await store.apiToken() == "")
        #expect(await store.appLanguageCode() == "system")
        #expect(await store.appearanceMode() == "system")
    }

    @Test
    func userDefaultsStorePersistsServerAndToken() async {
        let suiteName = "im.unhappy.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("failed to create UserDefaults test suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        await store.setServerURLString("https://api.example.com")
        await store.setAPIToken("secret")
        await store.setAppLanguageCode("korean")
        await store.setAppearanceMode("dark")

        #expect(await store.serverURLString() == "https://api.example.com")
        #expect(await store.apiToken() == "secret")
        #expect(await store.appLanguageCode() == "korean")
        #expect(await store.appearanceMode() == "dark")
    }
}
