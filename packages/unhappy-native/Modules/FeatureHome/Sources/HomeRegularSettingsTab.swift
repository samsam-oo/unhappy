import SwiftUI
import FeatureMachine
import FeatureSettings

private enum HomeRegularSettingsSelection: String, Hashable, CaseIterable {
    case account
    case restore
    case server
    case connectors
    case terminal
    case language
    case appearance
    case features
    case profiles
    case voice
    case usage
    case changelog
    case machines

    var title: String {
        switch self {
        case .account: return "Account"
        case .restore: return "Restore"
        case .server: return "Server"
        case .connectors: return "Connectors"
        case .terminal: return "Terminal"
        case .language: return "Language"
        case .appearance: return "Appearance"
        case .features: return "Features"
        case .profiles: return "Profiles"
        case .voice: return "Voice"
        case .usage: return "Usage"
        case .changelog: return "Changelog"
        case .machines: return "Manage Machines"
        }
    }

    var systemImage: String {
        switch self {
        case .account: return "person.crop.circle"
        case .restore: return "qrcode.viewfinder"
        case .server: return "server.rack"
        case .connectors: return "link"
        case .terminal: return "terminal"
        case .language: return "globe"
        case .appearance: return "circle.lefthalf.filled"
        case .features: return "slider.horizontal.3"
        case .profiles: return "person.2"
        case .voice: return "waveform"
        case .usage: return "chart.bar.xaxis"
        case .changelog: return "text.book.closed"
        case .machines: return "desktopcomputer"
        }
    }
}

@MainActor
struct HomeRegularSettingsTab: View {
    @ObservedObject var viewModel: SettingsViewModel
    let makeMachinesViewModel: @MainActor () -> MachinesViewModel
    let makeUsageViewModel: @MainActor () -> UsageSettingsViewModel
    let makeDaemonStatusViewModel: @MainActor () -> ConnectorsDaemonStatusViewModel
    let makeTerminalConnectViewModel: @MainActor () -> TerminalConnectSettingsViewModel
    let makeAccountLinkViewModel: @MainActor () -> AccountLinkSettingsViewModel

    @State private var selection: HomeRegularSettingsSelection = .account

    var body: some View {
        HStack(spacing: 0) {
            sidebarNavigation
                .frame(width: 340)
            Divider()
            detail
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var sidebarNavigation: some View {
        NavigationStack {
            sidebar
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.large)
        }
    }

    private var sidebar: some View {
        List {
            Section("Connection") {
                settingsRow(.account)
                settingsRow(.restore)
                settingsRow(.server)
                settingsRow(.connectors)
                settingsRow(.terminal)
            }

            Section("Preferences") {
                settingsRow(.language)
                settingsRow(.appearance)
                settingsRow(.features)
                settingsRow(.profiles)
                settingsRow(.voice)
                settingsRow(.usage)
                settingsRow(.changelog)
            }

            Section("Machine") {
                settingsRow(.machines)
            }
        }
        .listStyle(.plain)
        .contentMargins(.top, 8, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .systemBackground))
    }

    private func settingsRow(_ item: HomeRegularSettingsSelection) -> some View {
        Button {
            selection = item
        } label: {
            HStack(spacing: 12) {
                Label(item.title, systemImage: item.systemImage)
                Spacer()
                if selection == item {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var detail: some View {
        NavigationStack {
            switch selection {
            case .account:
                AccountSettingsView(
                    viewModel: viewModel,
                    makeAccountLinkViewModel: makeAccountLinkViewModel
                )
            case .restore:
                AccountRestoreView(
                    viewModel: viewModel,
                    makeAccountLinkViewModel: makeAccountLinkViewModel
                )
            case .server:
                ServerSettingsView(viewModel: viewModel)
            case .connectors:
                ConnectorsSettingsView(
                    serverURLString: viewModel.serverURLString,
                    token: viewModel.apiToken,
                    makeDaemonStatusViewModel: makeDaemonStatusViewModel
                )
            case .terminal:
                TerminalConnectSettingsView(
                    serverURLString: viewModel.serverURLString,
                    token: viewModel.apiToken,
                    makeViewModel: makeTerminalConnectViewModel
                )
            case .language:
                LanguageSettingsView(viewModel: viewModel)
            case .appearance:
                AppearanceSettingsView(viewModel: viewModel)
            case .features:
                FeaturesSettingsView(viewModel: viewModel)
            case .profiles:
                ProfilesSettingsView(viewModel: viewModel)
            case .voice:
                VoiceSettingsView(viewModel: viewModel)
            case .usage:
                UsageSettingsView(
                    serverURLString: viewModel.serverURLString,
                    token: viewModel.apiToken,
                    makeViewModel: makeUsageViewModel
                )
            case .changelog:
                ChangelogView()
                    .onAppear {
                        viewModel.markLatestChangelogViewed()
                    }
            case .machines:
                MachinesView(
                    serverURLString: viewModel.serverURLString,
                    token: viewModel.apiToken,
                    makeViewModel: makeMachinesViewModel
                )
            }
        }
    }
}
