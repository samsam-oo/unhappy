import Testing
@testable import FeatureHome
import FeatureSessions
import CoreKit

@MainActor
struct FeatureHomeTests {
    @Test
    func homeViewCanInitialize() {
        _ = HomeView(
            makeHomeViewModel: {
                HomeViewModel(store: MockAppSettingsStore())
            },
            makeSessionsViewModel: {
                SessionsViewModel(service: URLSessionSessionsService())
            }
        )
    }
}

private actor MockAppSettingsStore: AppSettingsStore {
    func serverURLString() async -> String { "https://api.unhappy.im" }
    func apiToken() async -> String { "" }
    func setServerURLString(_ value: String) async {}
    func setAPIToken(_ value: String) async {}
}
