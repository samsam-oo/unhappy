import Foundation
import Testing
@testable import CoreKit

struct AppSettingsStoreTests {
    @Test
    func userDefaultsStoreReturnsDefaultServerWhenMissing() async throws {
        let fixture = try makeFixture(
            defaultServerURL: "https://default.example.com"
        )
        defer { fixture.tearDown() }

        #expect(await fixture.store.serverURLString() == "https://default.example.com")
        #expect(await fixture.store.apiToken() == "")
        #expect(await fixture.store.appLanguageCode() == "system")
        #expect(await fixture.store.appearanceMode() == "system")
        #expect(await fixture.store.experimentsEnabled() == false)
        #expect(await fixture.store.hideInactiveSessions() == false)
        #expect(await fixture.store.useEnhancedSessionWizard() == false)
        #expect(await fixture.store.voiceEnabled() == false)
        #expect(await fixture.store.voiceLanguageCode() == "system")
        #expect(await fixture.store.defaultNewSessionAgent() == "claude")
        #expect(await fixture.store.lastViewedChangelogID() == "")
        #expect(await fixture.store.recentProjectPaths().isEmpty)
    }

    @Test
    func userDefaultsStorePersistsServerAndToken() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        await fixture.store.setServerURLString("https://api.example.com")
        await fixture.store.setAPIToken("secret")
        await fixture.store.setAppLanguageCode("korean")
        await fixture.store.setAppearanceMode("dark")
        await fixture.store.setExperimentsEnabled(true)
        await fixture.store.setHideInactiveSessions(true)
        await fixture.store.setUseEnhancedSessionWizard(true)
        await fixture.store.setVoiceEnabled(true)
        await fixture.store.setVoiceLanguageCode("korean")
        await fixture.store.setDefaultNewSessionAgent("codex")
        await fixture.store.setLastViewedChangelogID("2026.02.25")
        await fixture.store.setRecentProjectPaths([
            " /repo/alpha ",
            "",
            "/repo/beta"
        ])

        #expect(await fixture.store.serverURLString() == "https://api.example.com")
        #expect(await fixture.store.apiToken() == "secret")
        #expect(await fixture.store.appLanguageCode() == "korean")
        #expect(await fixture.store.appearanceMode() == "dark")
        #expect(await fixture.store.experimentsEnabled() == true)
        #expect(await fixture.store.hideInactiveSessions() == true)
        #expect(await fixture.store.useEnhancedSessionWizard() == true)
        #expect(await fixture.store.voiceEnabled() == true)
        #expect(await fixture.store.voiceLanguageCode() == "korean")
        #expect(await fixture.store.defaultNewSessionAgent() == "codex")
        #expect(await fixture.store.lastViewedChangelogID() == "2026.02.25")
        #expect(await fixture.store.recentProjectPaths() == ["/repo/alpha", "/repo/beta"])
    }
}

private struct AppSettingsStoreFixture {
    let suiteName: String
    let store: UserDefaultsAppSettingsStore

    func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }
}

private enum AppSettingsStoreFixtureError: Error {
    case failedToCreateSuite
}

private func makeFixture(
    defaultServerURL: String = "https://api.unhappy.im"
) throws -> AppSettingsStoreFixture {
    let suiteName = "im.unhappy.tests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw AppSettingsStoreFixtureError.failedToCreateSuite
    }

    return AppSettingsStoreFixture(
        suiteName: suiteName,
        store: UserDefaultsAppSettingsStore(
            defaults: defaults,
            defaultServerURL: defaultServerURL
        )
    )
}
