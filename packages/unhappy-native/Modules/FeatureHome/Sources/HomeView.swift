import SwiftUI
import CoreKit
import FeatureInbox
import FeatureMachine
import FeatureNewSession
import FeatureSessions
import FeatureSessionTools
import FeatureSettings

@MainActor
public struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var settingsViewModel: SettingsViewModel
    @StateObject private var serverStatusViewModel: HomeServerConnectionStatusViewModel
    @State private var isCreatingAccount = false
    @State private var onboardingErrorMessage: String?
    @State private var onboardingStatusMessage: String?
    @State private var isRestoreNavigationPresented = false
    @State private var isServerSettingsPresented = false
    private let onboarding: any HomeAccountOnboardingAction
    private let makeInboxViewModel: @MainActor () -> InboxViewModel
    private let makeSessionsViewModel: @MainActor () -> SessionsViewModel
    private let makeNewSessionViewModel: @MainActor () -> NewSessionViewModel
    private let makeSessionToolsViewModel: @MainActor () -> SessionToolsViewModel
    private let makeMachinesViewModel: @MainActor () -> MachinesViewModel
    private let makeUsageViewModel: @MainActor () -> UsageSettingsViewModel
    private let makeDaemonStatusViewModel: @MainActor () -> ConnectorsDaemonStatusViewModel
    private let makeTerminalConnectViewModel: @MainActor () -> TerminalConnectSettingsViewModel
    private let makeAccountLinkViewModel: @MainActor () -> AccountLinkSettingsViewModel

    public init(
        onboarding: any HomeAccountOnboardingAction,
        makeSettingsViewModel: @escaping @MainActor () -> SettingsViewModel,
        makeInboxViewModel: @escaping @MainActor () -> InboxViewModel,
        makeSessionsViewModel: @escaping @MainActor () -> SessionsViewModel,
        makeNewSessionViewModel: @escaping @MainActor () -> NewSessionViewModel,
        makeSessionToolsViewModel: @escaping @MainActor () -> SessionToolsViewModel,
        makeMachinesViewModel: @escaping @MainActor () -> MachinesViewModel,
        makeUsageViewModel: @escaping @MainActor () -> UsageSettingsViewModel,
        makeDaemonStatusViewModel: @escaping @MainActor () -> ConnectorsDaemonStatusViewModel,
        makeTerminalConnectViewModel: @escaping @MainActor () -> TerminalConnectSettingsViewModel,
        makeAccountLinkViewModel: @escaping @MainActor () -> AccountLinkSettingsViewModel,
        makeServerStatusViewModel: @escaping @MainActor () -> HomeServerConnectionStatusViewModel
    ) {
        self.onboarding = onboarding
        _settingsViewModel = StateObject(wrappedValue: makeSettingsViewModel())
        _serverStatusViewModel = StateObject(wrappedValue: makeServerStatusViewModel())
        self.makeInboxViewModel = makeInboxViewModel
        self.makeSessionsViewModel = makeSessionsViewModel
        self.makeNewSessionViewModel = makeNewSessionViewModel
        self.makeSessionToolsViewModel = makeSessionToolsViewModel
        self.makeMachinesViewModel = makeMachinesViewModel
        self.makeUsageViewModel = makeUsageViewModel
        self.makeDaemonStatusViewModel = makeDaemonStatusViewModel
        self.makeTerminalConnectViewModel = makeTerminalConnectViewModel
        self.makeAccountLinkViewModel = makeAccountLinkViewModel
    }

    public var body: some View {
        Group {
            if hasToken {
                authenticatedHome
            } else {
                unauthenticatedHome
            }
        }
        .task {
            await settingsViewModel.loadFromStore()
        }
    }

    private var hasToken: Bool {
        !settingsViewModel.apiToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private var authenticatedHome: some View {
        TabView {
            InboxView(
                serverURLString: settingsViewModel.serverURLString,
                token: settingsViewModel.apiToken,
                makeViewModel: makeInboxViewModel
            )
                .tabItem {
                    Label("Inbox", systemImage: "tray.full")
                }

            SessionsView(
                serverURLString: settingsViewModel.serverURLString,
                token: settingsViewModel.apiToken,
                hideInactiveSessions: settingsViewModel.hideInactiveSessions,
                defaultNewSessionAgent: settingsViewModel.defaultNewSessionAgent,
                makeViewModel: makeSessionsViewModel,
                makeNewSessionViewModel: makeNewSessionViewModel,
                makeSessionToolsViewModel: makeSessionToolsViewModel
            )
                .tabItem {
                    Label("Sessions", systemImage: "bubble.left.and.bubble.right")
                }

            SettingsView(
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
        }
    }

    private var unauthenticatedHome: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.97, blue: 1.0),
                            Color(red: 0.98, green: 0.99, blue: 1.0),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    ScrollView {
                        if proxy.size.width > proxy.size.height {
                            landscapeOnboardingLayout
                                .padding(.horizontal, 36)
                                .padding(.vertical, 28)
                        } else {
                            portraitOnboardingLayout
                                .padding(.horizontal, 24)
                                .padding(.vertical, 32)
                        }
                    }
                    .frame(maxWidth: 960)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image(systemName: "bolt.shield.fill")
                        .foregroundStyle(.blue)
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Sessions")
                            .font(.headline)
                        if let subtitle = customServerSubtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            connectionStatusView
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isServerSettingsPresented = true
                    } label: {
                        Image(systemName: "server.rack")
                    }
                    .accessibilityLabel("Open Server Settings")
                }
            }
            .navigationDestination(isPresented: $isRestoreNavigationPresented) {
                AccountRestoreView(
                    viewModel: settingsViewModel,
                    makeAccountLinkViewModel: makeAccountLinkViewModel
                )
            }
            .navigationDestination(isPresented: $isServerSettingsPresented) {
                ServerSettingsView(viewModel: settingsViewModel)
            }
            .task(id: statusPollingTaskKey) {
                await pollServerStatus()
            }
        }
    }

    private var isPhoneLayout: Bool {
        horizontalSizeClass != .regular
    }

    private var portraitOnboardingLayout: some View {
        VStack(spacing: 24) {
            onboardingBranding
            featureBadgesRow
            serverInput
            onboardingActions
            onboardingFeedback
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    private var landscapeOnboardingLayout: some View {
        HStack(spacing: 24) {
            VStack(spacing: 18) {
                onboardingBranding
                featureBadgesRow
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 20) {
                serverInput
                onboardingActions
                onboardingFeedback
            }
            .frame(maxWidth: 360)
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        .frame(maxWidth: .infinity)
    }

    private var onboardingBranding: some View {
        VStack(spacing: 10) {
            Image(systemName: "bolt.shield.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.blue)
            Text("Unhappy Coder")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("Launch your first secure session in seconds.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var featureBadgesRow: some View {
        HStack(spacing: 8) {
            featureBadge(title: "Encrypted", systemImage: "lock.fill")
            featureBadge(title: "Cross Platform", systemImage: "globe")
            featureBadge(title: "Fast Restore", systemImage: "bolt.fill")
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 6)
    }

    private var serverInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Server")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField("https://api.unhappy.im", text: $settingsViewModel.serverURLString)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.body.monospaced())
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var onboardingActions: some View {
        VStack(spacing: 10) {
            if isPhoneLayout {
                createAccountButton(isPrimary: true)
                restoreAccountButton(title: "Link or Restore Account", isPrimary: false)
            } else {
                restoreAccountButton(title: "Login With Mobile App", isPrimary: true)
                createAccountButton(isPrimary: false)
            }
        }
    }

    @ViewBuilder
    private var onboardingFeedback: some View {
        if let onboardingStatusMessage {
            Text(onboardingStatusMessage)
                .font(.footnote)
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let onboardingErrorMessage {
            Text(onboardingErrorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func createAccountButton(isPrimary: Bool) -> some View {
        if isPrimary {
            Button(action: createAccount) {
                HStack(spacing: 10) {
                    if isCreatingAccount {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isCreatingAccount ? "Creating Account..." : "Create Account")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCreatingAccount)
        } else {
            Button(action: createAccount) {
                HStack(spacing: 10) {
                    if isCreatingAccount {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isCreatingAccount ? "Creating Account..." : "Create Account")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .disabled(isCreatingAccount)
        }
    }

    @ViewBuilder
    private func restoreAccountButton(title: String, isPrimary: Bool) -> some View {
        if isPrimary {
            Button(title) {
                onboardingErrorMessage = nil
                onboardingStatusMessage = nil
                isRestoreNavigationPresented = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCreatingAccount)
        } else {
            Button(title) {
                onboardingErrorMessage = nil
                onboardingStatusMessage = nil
                isRestoreNavigationPresented = true
            }
            .buttonStyle(.bordered)
            .disabled(isCreatingAccount)
        }
    }

    private func featureBadge(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }

    private func createAccount() {
        onboardingErrorMessage = nil
        onboardingStatusMessage = nil
        let serverURLString = settingsViewModel.serverURLString
        isCreatingAccount = true

        Task {
            defer { isCreatingAccount = false }
            do {
                let token = try await onboarding.createAccount(serverURLString: serverURLString)
                settingsViewModel.apiToken = token
                onboardingStatusMessage = "Account created successfully"
            } catch {
                onboardingErrorMessage = onboardingErrorDescription(error)
            }
        }
    }

    private func onboardingErrorDescription(_ error: Error) -> String {
        if let onboardingError = error as? HomeAccountOnboardingError,
           let description = onboardingError.errorDescription {
            return description
        }
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    private var customServerSubtitle: String? {
        let trimmed = settingsViewModel.serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host else {
            return nil
        }
        let isDefaultHost = host.caseInsensitiveCompare("api.unhappy.im") == .orderedSame
            && (url.port == nil || url.port == 443)
        guard !isDefaultHost else {
            return nil
        }
        if let port = url.port {
            return "\(host):\(port)"
        }
        return host
    }

    private var statusPollingTaskKey: String {
        settingsViewModel.serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        HStack(spacing: 4) {
            if connectionStatus == .connecting {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Circle()
                    .fill(connectionStatusColor)
                    .frame(width: 6, height: 6)
            }
            Text(connectionStatusText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(connectionStatusColor)
        }
        .accessibilityLabel("Server status \(connectionStatusText)")
    }

    private var connectionStatus: HomeServerConnectionStatus {
        if serverStatusViewModel.isLoading {
            return .connecting
        }
        return serverStatusViewModel.status
    }

    private var connectionStatusText: String {
        switch connectionStatus {
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .disconnected:
            return "Disconnected"
        }
    }

    private var connectionStatusColor: Color {
        switch connectionStatus {
        case .connecting:
            return .orange
        case .connected:
            return .green
        case .disconnected:
            return .secondary
        }
    }

    private func pollServerStatus() async {
        while !Task.isCancelled {
            await serverStatusViewModel.refresh(serverURLString: settingsViewModel.serverURLString)

            do {
                try await Task.sleep(for: .seconds(8))
            } catch {
                return
            }
        }
    }
}

#Preview {
    HomeView(
        onboarding: PreviewHomeAccountOnboarding(),
        makeSettingsViewModel: {
            SettingsViewModel(
                settingsManager: SettingsUseCase(store: UserDefaultsAppSettingsStore())
            )
        },
        makeInboxViewModel: {
            let friendsService = URLSessionFriendsService()
            let usersService = URLSessionUsersService()
            return InboxViewModel(
                loader: InboxLoadUseCase(
                    service: URLSessionFeedService(),
                    friendsService: friendsService
                ),
                friendAction: InboxFriendActionUseCase(
                    adder: friendsService,
                    remover: friendsService
                ),
                userProfileLoader: InboxUserProfileLoadUseCase(service: usersService),
                userSearcher: InboxUserSearchUseCase(service: usersService)
            )
        },
        makeSessionsViewModel: { SessionsViewModel(service: URLSessionSessionsService()) },
        makeNewSessionViewModel: {
            let service = URLSessionMachinesService()
            return NewSessionViewModel(
                machinesLoader: NewSessionMachinesLoadUseCase(service: service),
                directoryLister: NewSessionDirectoryListUseCase(service: service),
                spawner: NewSessionSpawnUseCase(service: service),
                recentProjectsManager: NewSessionNoopRecentProjectsManager(),
                profilesManager: NewSessionNoopProfilesManager()
            )
        },
        makeSessionToolsViewModel: {
            let service = URLSessionSessionsService()
            let basher = SessionBashUseCase(service: service)
            return SessionToolsViewModel(
                fileLoader: SessionFileLoadUseCase(service: service),
                directoryLister: SessionDirectoryListUseCase(service: service),
                fileWriter: SessionFileWriteUseCase(service: service),
                fileDiffPreviewer: SessionFileDiffPreviewUseCase(basher: basher),
                killer: SessionKillUseCase(service: service),
                aborter: SessionTaskAbortUseCase(service: service),
                permissionResponder: SessionPermissionUseCase(service: service),
                modeSwitcher: SessionModeSwitchUseCase(service: service),
                basher: basher,
                ripgrepRunner: SessionRipgrepUseCase(service: service),
                difftasticRunner: SessionDifftasticUseCase(service: service)
            )
        },
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
                    encryptor: TweetNaclTerminalAuthEncryptor()
                )
            )
        },
        makeAccountLinkViewModel: {
            AccountLinkSettingsViewModel(
                linker: AccountLinkUseCase(
                    service: URLSessionAccountAuthService(),
                    encryptor: TweetNaclTerminalAuthEncryptor()
                ),
                restorer: AccountRestoreUseCase(
                    authTokenService: URLSessionAuthTokenService()
                ),
                qrRestorer: AccountRestoreQRUseCase(
                    requestService: URLSessionAccountRestoreRequestService()
                ),
                secretStore: UserDefaultsAccountSecretStore()
            )
        },
        makeServerStatusViewModel: {
            HomeServerConnectionStatusViewModel(
                loader: HomeServerConnectionStatusLoadUseCase()
            )
        }
    )
}

private actor PreviewHomeAccountOnboarding: HomeAccountOnboardingAction {
    func createAccount(serverURLString: String) async throws -> String {
        "preview-token"
    }
}
