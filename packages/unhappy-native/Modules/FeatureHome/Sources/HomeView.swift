import SwiftUI
import CoreKit
import FeatureSessions
import FeatureSettings

@MainActor
public struct HomeView: View {
    @StateObject private var settingsViewModel: SettingsViewModel
    private let makeSessionsViewModel: @MainActor () -> SessionsViewModel

    public init(
        makeSettingsViewModel: @escaping @MainActor () -> SettingsViewModel,
        makeSessionsViewModel: @escaping @MainActor () -> SessionsViewModel
    ) {
        _settingsViewModel = StateObject(wrappedValue: makeSettingsViewModel())
        self.makeSessionsViewModel = makeSessionsViewModel
    }

    public var body: some View {
        TabView {
            SessionsView(
                serverURLString: settingsViewModel.serverURLString,
                token: settingsViewModel.apiToken,
                makeViewModel: makeSessionsViewModel
            )
                .tabItem {
                    Label("Sessions", systemImage: "bubble.left.and.bubble.right")
                }

            SettingsView(viewModel: settingsViewModel)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .task {
            await settingsViewModel.loadFromStore()
        }
    }
}

#Preview {
    HomeView(
        makeSettingsViewModel: {
            SettingsViewModel(
                settingsManager: SettingsUseCase(store: UserDefaultsAppSettingsStore())
            )
        },
        makeSessionsViewModel: { SessionsViewModel(service: URLSessionSessionsService()) }
    )
}
