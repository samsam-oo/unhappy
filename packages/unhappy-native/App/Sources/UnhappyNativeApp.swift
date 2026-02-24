import SwiftUI
import CoreKit
import FeatureHome
import FeatureSessions
import FeatureSettings

@main
struct UnhappyNativeApp: App {
    private let makeHomeViewModel: @MainActor () -> HomeViewModel
    private let makeSessionsViewModel: @MainActor () -> SessionsViewModel

    init() {
        let settingsStore = UserDefaultsAppSettingsStore()
        let settingsUseCase = SettingsUseCase(store: settingsStore)
        let sessionsService = URLSessionSessionsService()
        self.makeHomeViewModel = { HomeViewModel(settingsManager: settingsUseCase) }
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
