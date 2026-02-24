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

private final class MockAppSettingsStore: AppSettingsStore {
    func serverURLString() -> String { "https://api.unhappy.im" }
    func apiToken() -> String { "" }
    func setServerURLString(_ value: String) {}
    func setAPIToken(_ value: String) {}
}
