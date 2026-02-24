import Testing
@testable import FeatureHome
import FeatureSessions
import CoreKit
import FeatureSettings

@MainActor
struct FeatureHomeTests {
    @Test
    func homeViewCanInitialize() {
        _ = HomeView(
            makeHomeViewModel: {
                HomeViewModel(settingsManager: MockSettingsManager())
            },
            makeSessionsViewModel: {
                SessionsViewModel(service: URLSessionSessionsService())
            }
        )
    }
}

private actor MockSettingsManager: SettingsManaging {
    func loadSettings() async -> AppSettingsSnapshot {
        AppSettingsSnapshot(serverURLString: "https://api.unhappy.im", apiToken: "")
    }

    func persistSettings(serverURLString: String, apiToken: String) async {}
}
