import SwiftUI
import CoreKit
import FeatureHome
import FeatureSessions

@main
struct UnhappyNativeApp: App {
    private let makeHomeViewModel: @MainActor () -> HomeViewModel
    private let makeSessionsViewModel: @MainActor () -> SessionsViewModel

    init() {
        let settingsStore = UserDefaultsAppSettingsStore()
        let sessionsService = URLSessionSessionsService()
        self.makeHomeViewModel = { HomeViewModel(store: settingsStore) }
        self.makeSessionsViewModel = { SessionsViewModel(service: sessionsService) }
    }

    var body: some Scene {
        WindowGroup {
            HomeView(
                makeHomeViewModel: makeHomeViewModel,
                makeSessionsViewModel: makeSessionsViewModel
            )
        }
    }
}
