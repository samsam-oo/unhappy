import SwiftUI
import CoreKit
import FeatureSessions
import FeatureSettings

@MainActor
public struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel
    private let makeSessionsViewModel: @MainActor () -> SessionsViewModel

    public init(
        makeHomeViewModel: @escaping @MainActor () -> HomeViewModel,
        makeSessionsViewModel: @escaping @MainActor () -> SessionsViewModel
    ) {
        _viewModel = StateObject(wrappedValue: makeHomeViewModel())
        self.makeSessionsViewModel = makeSessionsViewModel
    }

    public var body: some View {
        TabView {
            SessionsView(
                serverURLString: viewModel.serverURLString,
                token: viewModel.apiToken,
                makeViewModel: makeSessionsViewModel
            )
                .tabItem {
                    Label("Sessions", systemImage: "bubble.left.and.bubble.right")
                }

            SettingsView(
                serverURLString: $viewModel.serverURLString,
                apiToken: $viewModel.apiToken
            )
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    HomeView(
        makeHomeViewModel: { HomeViewModel(store: UserDefaultsAppSettingsStore()) },
        makeSessionsViewModel: { SessionsViewModel(service: URLSessionSessionsService()) }
    )
}
