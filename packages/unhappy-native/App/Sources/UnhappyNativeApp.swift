import SwiftUI
import CoreKit
import FeatureHome
import FeatureSessions

@main
struct UnhappyNativeApp: App {
    private let makeSessionsViewModel: @MainActor () -> SessionsViewModel

    init() {
        let sessionsService = URLSessionSessionsService()
        self.makeSessionsViewModel = { SessionsViewModel(service: sessionsService) }
    }

    var body: some Scene {
        WindowGroup {
            HomeView(makeSessionsViewModel: makeSessionsViewModel)
        }
    }
}
