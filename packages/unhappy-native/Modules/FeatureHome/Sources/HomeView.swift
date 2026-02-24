import SwiftUI
import CoreKit
import FeatureSessions
import FeatureSettings

public struct HomeView: View {
    @AppStorage("unhappy.native.serverURL") private var serverURLString = "https://api.unhappy.im"
    @AppStorage("unhappy.native.apiToken") private var apiToken = ""
    private let makeSessionsViewModel: @MainActor () -> SessionsViewModel

    public init(makeSessionsViewModel: @escaping @MainActor () -> SessionsViewModel) {
        self.makeSessionsViewModel = makeSessionsViewModel
    }

    public var body: some View {
        TabView {
            SessionsView(
                serverURLString: serverURLString,
                token: apiToken,
                makeViewModel: makeSessionsViewModel
            )
                .tabItem {
                    Label("Sessions", systemImage: "bubble.left.and.bubble.right")
                }

            SettingsView(serverURLString: $serverURLString, apiToken: $apiToken)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    HomeView(
        makeSessionsViewModel: { SessionsViewModel(service: URLSessionSessionsService()) }
    )
}
