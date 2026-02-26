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
        #expect(await store.experimentsEnabled() == false)
        #expect(await store.hideInactiveSessions() == false)
        #expect(await store.useEnhancedSessionWizard() == false)
        #expect(await store.voiceEnabled() == false)
        #expect(await store.voiceLanguageCode() == "system")
        #expect(await store.defaultNewSessionAgent() == "claude")
        #expect(await store.recentProjectPaths().isEmpty)
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
        await store.setExperimentsEnabled(true)
        await store.setHideInactiveSessions(true)
        await store.setUseEnhancedSessionWizard(true)
        await store.setVoiceEnabled(true)
        await store.setVoiceLanguageCode("korean")
        await store.setDefaultNewSessionAgent("codex")
        await store.setRecentProjectPaths([
            " /repo/alpha ",
            "",
            "/repo/beta"
        ])

        #expect(await store.serverURLString() == "https://api.example.com")
        #expect(await store.apiToken() == "secret")
        #expect(await store.appLanguageCode() == "korean")
        #expect(await store.appearanceMode() == "dark")
        #expect(await store.experimentsEnabled() == true)
        #expect(await store.hideInactiveSessions() == true)
        #expect(await store.useEnhancedSessionWizard() == true)
        #expect(await store.voiceEnabled() == true)
        #expect(await store.voiceLanguageCode() == "korean")
        #expect(await store.defaultNewSessionAgent() == "codex")
        #expect(await store.recentProjectPaths() == ["/repo/alpha", "/repo/beta"])
    }
}
