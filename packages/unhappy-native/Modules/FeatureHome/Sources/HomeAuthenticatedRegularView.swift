import SwiftUI
import CoreKit
import SessionKit
import FeatureInbox
import FeatureMachine
import FeatureNewSession
import FeatureSessions
import FeatureSettings

@MainActor
struct HomeAuthenticatedRegularView: View {
    private enum AuthenticatedTab: Hashable {
        case projects
        case inbox
        case settings
    }

    @ObservedObject var settingsViewModel: SettingsViewModel
    let serverURLString: String
    let token: String
    let hideInactiveSessions: Bool
    let defaultNewSessionAgent: APISessionSpawnAgent
    let makeNewSessionViewModel: @MainActor () -> NewSessionViewModel
    let makeProjectStartSheet: SessionProjectStartSheetBuilder
    let makeDirectSessionViewModel: @MainActor (DirectSessionIdentity) -> DirectSessionViewModel
    let makeMachinesViewModel: @MainActor () -> MachinesViewModel
    let makeUsageViewModel: @MainActor () -> UsageSettingsViewModel
    let makeDaemonStatusViewModel: @MainActor () -> ConnectorsDaemonStatusViewModel
    let makeTerminalConnectViewModel: @MainActor () -> TerminalConnectSettingsViewModel
    let makeAccountLinkViewModel: @MainActor () -> AccountLinkSettingsViewModel

    @StateObject private var inboxViewModel: InboxViewModel
    @StateObject private var sessionsViewModel: SessionsViewModel
    @State private var selectedTab: AuthenticatedTab = .projects

    init(
        settingsViewModel: SettingsViewModel,
        serverURLString: String,
        token: String,
        hideInactiveSessions: Bool,
        defaultNewSessionAgent: APISessionSpawnAgent,
        makeInboxViewModel: @escaping @MainActor () -> InboxViewModel,
        makeSessionsViewModel: @escaping @MainActor () -> SessionsViewModel,
        makeNewSessionViewModel: @escaping @MainActor () -> NewSessionViewModel,
        makeProjectStartSheet: @escaping SessionProjectStartSheetBuilder,
        makeDirectSessionViewModel: @escaping @MainActor (DirectSessionIdentity) -> DirectSessionViewModel,
        makeMachinesViewModel: @escaping @MainActor () -> MachinesViewModel,
        makeUsageViewModel: @escaping @MainActor () -> UsageSettingsViewModel,
        makeDaemonStatusViewModel: @escaping @MainActor () -> ConnectorsDaemonStatusViewModel,
        makeTerminalConnectViewModel: @escaping @MainActor () -> TerminalConnectSettingsViewModel,
        makeAccountLinkViewModel: @escaping @MainActor () -> AccountLinkSettingsViewModel
    ) {
        self.settingsViewModel = settingsViewModel
        self.serverURLString = serverURLString
        self.token = token
        self.hideInactiveSessions = hideInactiveSessions
        self.defaultNewSessionAgent = defaultNewSessionAgent
        self.makeNewSessionViewModel = makeNewSessionViewModel
        self.makeProjectStartSheet = makeProjectStartSheet
        self.makeDirectSessionViewModel = makeDirectSessionViewModel
        self.makeMachinesViewModel = makeMachinesViewModel
        self.makeUsageViewModel = makeUsageViewModel
        self.makeDaemonStatusViewModel = makeDaemonStatusViewModel
        self.makeTerminalConnectViewModel = makeTerminalConnectViewModel
        self.makeAccountLinkViewModel = makeAccountLinkViewModel
        _inboxViewModel = StateObject(wrappedValue: makeInboxViewModel())
        _sessionsViewModel = StateObject(wrappedValue: makeSessionsViewModel())
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeRegularProjectsTab(
                viewModel: sessionsViewModel,
                serverURLString: serverURLString,
                token: token,
                hideInactiveSessions: hideInactiveSessions,
                defaultNewSessionAgent: defaultNewSessionAgent,
                makeNewSessionViewModel: makeNewSessionViewModel,
                makeProjectStartSheet: makeProjectStartSheet,
                makeDirectSessionViewModel: makeDirectSessionViewModel,
            )
            .tabItem {
                Label("Projects", systemImage: "folder")
            }
            .tag(AuthenticatedTab.projects)

            HomeRegularInboxTab(
                viewModel: inboxViewModel,
                serverURLString: serverURLString,
                token: token
            )
            .tabItem {
                Label("Inbox", systemImage: "tray.full")
            }
            .tag(AuthenticatedTab.inbox)

            HomeRegularSettingsTab(
                viewModel: settingsViewModel,
                makeMachinesViewModel: makeMachinesViewModel,
                makeUsageViewModel: makeUsageViewModel,
                makeDaemonStatusViewModel: makeDaemonStatusViewModel,
                makeTerminalConnectViewModel: makeTerminalConnectViewModel,
                makeAccountLinkViewModel: makeAccountLinkViewModel
            )
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(AuthenticatedTab.settings)
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
