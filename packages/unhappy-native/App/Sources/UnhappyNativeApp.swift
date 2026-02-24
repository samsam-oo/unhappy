import SwiftUI
import CoreKit
import FeatureHome
import FeatureSessions
import FeatureSettings

@main
struct UnhappyNativeApp: App {
    private let makeSettingsViewModel: @MainActor () -> SettingsViewModel
    private let makeSessionsViewModel: @MainActor () -> SessionsViewModel

    init() {
        let settingsStore = UserDefaultsAppSettingsStore()
        let settingsUseCase = SettingsUseCase(store: settingsStore)
        let sessionsService = URLSessionSessionsService()
        self.makeSettingsViewModel = { SettingsViewModel(settingsManager: settingsUseCase) }
        self.makeSessionsViewModel = { SessionsViewModel(service: sessionsService) }
    }

    var body: some Scene {
        WindowGroup {
            HomeView(
                makeSettingsViewModel: makeSettingsViewModel,
                makeSessionsViewModel: makeSessionsViewModel
            )
        }
    }
}
