import SwiftUI
import FeatureSessions
import FeatureSettings

public struct HomeView: View {
    @AppStorage("unhappy.native.serverURL") private var serverURLString = "https://api.unhappy.im"
    @AppStorage("unhappy.native.apiToken") private var apiToken = ""

    public init() {}

    public var body: some View {
        TabView {
            SessionsView(serverURLString: serverURLString, token: apiToken)
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
    HomeView()
}
