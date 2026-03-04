import SwiftUI
import CoreKit
import FeatureMachine

@MainActor
public struct SettingsView: View {
    @ObservedObject private var viewModel: SettingsViewModel
    private let makeMachinesViewModel: @MainActor () -> MachinesViewModel
    private let makeUsageViewModel: @MainActor () -> UsageSettingsViewModel
    private let makeDaemonStatusViewModel: @MainActor () -> ConnectorsDaemonStatusViewModel
    private let makeTerminalConnectViewModel: @MainActor () -> TerminalConnectSettingsViewModel
    private let makeAccountLinkViewModel: @MainActor () -> AccountLinkSettingsViewModel

    public init(
        viewModel: SettingsViewModel,
        makeMachinesViewModel: @escaping @MainActor () -> MachinesViewModel,
        makeUsageViewModel: @escaping @MainActor () -> UsageSettingsViewModel,
        makeDaemonStatusViewModel: @escaping @MainActor () -> ConnectorsDaemonStatusViewModel,
        makeTerminalConnectViewModel: @escaping @MainActor () -> TerminalConnectSettingsViewModel,
        makeAccountLinkViewModel: @escaping @MainActor () -> AccountLinkSettingsViewModel
    ) {
        self.viewModel = viewModel
        self.makeMachinesViewModel = makeMachinesViewModel
        self.makeUsageViewModel = makeUsageViewModel
        self.makeDaemonStatusViewModel = makeDaemonStatusViewModel
        self.makeTerminalConnectViewModel = makeTerminalConnectViewModel
        self.makeAccountLinkViewModel = makeAccountLinkViewModel
    }

    public var body: some View {
        NavigationSplitView {
            settingsSidebarContent
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
                .navigationTitle("Settings")
        } detail: {
            splitDetailPlaceholder
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(detailCanvasColor)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var settingsSidebarContent: some View {
        List {
            Section("Connection") {
                NavigationLink {
                    AccountSettingsView(
                        viewModel: viewModel,
                        makeAccountLinkViewModel: makeAccountLinkViewModel
                    )
                } label: {
                    Label("Account", systemImage: "person.crop.circle")
                }
                NavigationLink {
                    AccountRestoreView(
                        viewModel: viewModel,
                        makeAccountLinkViewModel: makeAccountLinkViewModel
                    )
                } label: {
                    Label("Restore", systemImage: "qrcode.viewfinder")
                }
                NavigationLink {
                    ServerSettingsView(viewModel: viewModel)
                } label: {
                    Label("Server", systemImage: "server.rack")
                }
                NavigationLink {
                    ConnectorsSettingsView(
                        serverURLString: viewModel.serverURLString,
                        token: viewModel.apiToken,
                        makeDaemonStatusViewModel: makeDaemonStatusViewModel
                    )
                } label: {
                    Label("Connectors", systemImage: "link")
                }
                NavigationLink {
                    TerminalConnectSettingsView(
                        serverURLString: viewModel.serverURLString,
                        token: viewModel.apiToken,
                        makeViewModel: makeTerminalConnectViewModel
                    )
                } label: {
                    Label("Terminal", systemImage: "terminal")
                }
            }

            Section("Preferences") {
                NavigationLink {
                    LanguageSettingsView(viewModel: viewModel)
                } label: {
                    Label("Language", systemImage: "globe")
                }
                NavigationLink {
                    AppearanceSettingsView(viewModel: viewModel)
                } label: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }
                NavigationLink {
                    FeaturesSettingsView(viewModel: viewModel)
                } label: {
                    Label("Features", systemImage: "slider.horizontal.3")
                }
                NavigationLink {
                    ProfilesSettingsView(viewModel: viewModel)
                } label: {
                    Label("Profiles", systemImage: "person.2")
                }
                NavigationLink {
                    VoiceSettingsView(viewModel: viewModel)
                } label: {
                    Label("Voice", systemImage: "waveform")
                }
                NavigationLink {
                    UsageSettingsView(
                        serverURLString: viewModel.serverURLString,
                        token: viewModel.apiToken,
                        makeViewModel: makeUsageViewModel
                    )
                } label: {
                    Label("Usage", systemImage: "chart.bar.xaxis")
                }
                NavigationLink {
                    ChangelogView()
                        .onAppear {
                            viewModel.markLatestChangelogViewed()
                        }
                } label: {
                    ChangelogRow(hasUnread: viewModel.hasUnreadChangelog)
                }
            }

            Section("Machine") {
                NavigationLink {
                    MachinesView(
                        serverURLString: viewModel.serverURLString,
                        token: viewModel.apiToken,
                        makeViewModel: makeMachinesViewModel
                    )
                } label: {
                    Label("Manage Machines", systemImage: "desktopcomputer")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(sidebarCanvasColor)
    }

    private var splitDetailPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Select a Setting")
                .font(.headline)
            Text("Choose an item from the left panel to open details.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
    }

    private var sidebarCanvasColor: Color {
        Color(uiColor: .systemBackground)
    }

    private var detailCanvasColor: Color {
        Color(uiColor: .systemGroupedBackground)
    }
}

#Preview {
    SettingsView(
        viewModel: SettingsViewModel(settingsManager: PreviewSettingsManager()),
        makeMachinesViewModel: {
            let service = URLSessionMachinesService()
            return MachinesViewModel(
                loader: MachinesLoadUseCase(service: service),
                spawner: MachineSpawnUseCase(service: service),
                updater: MachineDaemonUpdateUseCase(service: service),
                stopper: MachineDaemonStopUseCase(service: service)
            )
        },
        makeUsageViewModel: {
            UsageSettingsViewModel(
                usageLoader: SettingsUsageLoadUseCase(service: URLSessionSessionsService())
            )
        },
        makeDaemonStatusViewModel: {
            ConnectorsDaemonStatusViewModel(
                loader: DaemonStatusLoadUseCase(service: URLSessionMachinesService())
            )
        },
        makeTerminalConnectViewModel: {
            TerminalConnectSettingsViewModel(
                connector: TerminalConnectUseCase(
                    service: URLSessionTerminalAuthService(),
                    dataKeyStore: UserDefaultsTerminalDataKeyStore(),
                    encryptor: CryptoKitTerminalAuthEncryptor()
                )
            )
        },
        makeAccountLinkViewModel: {
            AccountLinkSettingsViewModel(
                linker: AccountLinkUseCase(
                    service: URLSessionAccountAuthService(),
                    encryptor: CryptoKitTerminalAuthEncryptor()
                ),
                restorer: AccountRestoreUseCase(
                    authTokenService: URLSessionAuthTokenService()
                ),
                qrRestorer: AccountRestoreQRUseCase(
                    requestService: URLSessionAccountRestoreRequestService()
                ),
                secretStore: UserDefaultsAccountSecretStore()
            )
        }
    )
}

private actor PreviewSettingsManager: SettingsManaging {
    func loadSettings() async -> AppSettingsSnapshot {
        AppSettingsSnapshot(
            serverURLString: "https://api.unhappy.im",
            apiToken: "",
            appLanguage: .system,
            appearance: .system
        )
    }

    func persistSettings(
        serverURLString: String,
        apiToken: String,
        appLanguage: AppLanguageOption,
        appearance: AppAppearanceOption,
        experimentsEnabled: Bool,
        hideInactiveSessions: Bool,
        useEnhancedSessionWizard: Bool,
        voiceEnabled: Bool,
        voiceLanguage: AppVoiceLanguageOption,
        defaultNewSessionAgent: APISessionSpawnAgent,
        lastViewedChangelogID: String
    ) async {}
}

private struct ChangelogRow: View {
    let hasUnread: Bool

    var body: some View {
        HStack(spacing: 12) {
            Label("Changelog", systemImage: "text.book.closed")
            Spacer()
            if hasUnread {
                Text("NEW")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.accentColor)
                    )
                    .accessibilityLabel("Unread changelog updates")
            }
        }
    }
}
