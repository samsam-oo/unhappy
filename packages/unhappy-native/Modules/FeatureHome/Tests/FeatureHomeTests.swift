import Testing
@testable import FeatureHome
import FeatureSessions
import CoreKit

struct FeatureHomeTests {
    @Test
    func homeViewCanInitialize() {
        _ = HomeView(
            makeSessionsViewModel: {
                SessionsViewModel(service: URLSessionSessionsService())
            }
        )
    }
}
