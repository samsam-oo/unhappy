import SwiftUI
import CoreKit
import FeatureHome
import FeatureInbox
import FeatureMachine
import FeatureNewSession
import FeatureSessions
import FeatureSettings

@main
struct UnhappyNativeApp: App {
    @AppStorage("unhappy.native.appearanceMode")
    private var storedAppearanceMode = "system"

    private let onboarding: any HomeAccountOnboardingAction
    private let makeSettingsViewModel: @MainActor () -> SettingsViewModel
    private let makeInboxViewModel: @MainActor () -> InboxViewModel
    private let makeSessionsViewModel: @MainActor () -> SessionsViewModel
    private let makeNewSessionViewModel: @MainActor () -> NewSessionViewModel
    private let makeDirectSessionViewModel: @MainActor (DirectSessionIdentity) -> DirectSessionViewModel
    private let makeMachinesViewModel: @MainActor () -> MachinesViewModel
    private let makeUsageViewModel: @MainActor () -> UsageSettingsViewModel
    private let makeDaemonStatusViewModel: @MainActor () -> ConnectorsDaemonStatusViewModel
    private let makeTerminalConnectViewModel: @MainActor () -> TerminalConnectSettingsViewModel
    private let makeAccountLinkViewModel: @MainActor () -> AccountLinkSettingsViewModel
    private let makeServerStatusViewModel: @MainActor () -> HomeServerConnectionStatusViewModel

    init() {
        let settingsStore = UserDefaultsAppSettingsStore()
        let settingsUseCase = SettingsUseCase(store: settingsStore)
        let sessionsService = URLSessionSessionsService()
        let machinesService = URLSessionMachinesService()
        let feedService = URLSessionFeedService()
        let friendsService = URLSessionFriendsService()
        let usersService = URLSessionUsersService()
        let machinesLoader = MachinesLoadUseCase(service: machinesService)
        let machineSpawner = MachineSpawnUseCase(service: machinesService)
        let machineUpdater = MachineDaemonUpdateUseCase(service: machinesService)
        let machineStopper = MachineDaemonStopUseCase(service: machinesService)
        let newSessionMachinesLoader = NewSessionMachinesLoadUseCase(service: machinesService)
        let newSessionDirectoryLister = NewSessionDirectoryListUseCase(service: machinesService)
        let newSessionSpawner = NewSessionSpawnUseCase(service: machinesService)
        let upstreamSessionsLoader = SessionUpstreamSessionsLoadUseCase(service: machinesService)
        let newSessionModelsLoader = NewSessionModelsLoadUseCase(service: machinesService)
        let newSessionCodexThreadsLoader = NewSessionCodexThreadsLoadUseCase(service: machinesService)
        let newSessionClaudeSessionsLoader = NewSessionClaudeSessionsLoadUseCase(service: machinesService)
        let newSessionRecentProjects = NewSessionNoopRecentProjectsManager()
        let newSessionProfiles = NewSessionProfilesUseCase(store: UserDefaultsNewSessionProfilesStore())
        let usageLoader = SettingsUsageLoadUseCase(service: sessionsService)
        let daemonStatusLoader = DaemonStatusLoadUseCase(service: machinesService)
        let inboxLoader = InboxLoadUseCase(
            service: feedService,
            friendsService: friendsService
        )
        let inboxFriendAction = InboxFriendActionUseCase(
            adder: friendsService,
            remover: friendsService
        )
        let inboxUserProfileLoader = InboxUserProfileLoadUseCase(service: usersService)
        let inboxUserSearcher = InboxUserSearchUseCase(service: usersService)
        let homeServerStatusLoader = HomeServerConnectionStatusLoadUseCase()
        let terminalAuthService = URLSessionTerminalAuthService()
        let accountAuthService = URLSessionAccountAuthService()
        let accountRestoreRequestService = URLSessionAccountRestoreRequestService()
        let authTokenService = URLSessionAuthTokenService()
        let terminalDataKeyStore = UserDefaultsTerminalDataKeyStore()
        let accountSecretStore = UserDefaultsAccountSecretStore()
        let terminalConnectUseCase = TerminalConnectUseCase(
            service: terminalAuthService,
            dataKeyStore: terminalDataKeyStore,
            encryptor: CryptoKitTerminalAuthEncryptor()
        )
        let accountLinkUseCase = AccountLinkUseCase(
            service: accountAuthService,
            encryptor: CryptoKitTerminalAuthEncryptor()
        )
        let accountRestoreUseCase = AccountRestoreUseCase(authTokenService: authTokenService)
        let accountRestoreQRUseCase = AccountRestoreQRUseCase(
            requestService: accountRestoreRequestService
        )
        let onboardingUseCase = HomeAccountOnboardingUseCase(
            authTokenService: authTokenService,
            secretStore: accountSecretStore
        )
        let sessionsLoader = SessionsLoadUseCase(service: sessionsService)
        let sessionsPageLoader = SessionsPageLoadUseCase(service: sessionsService)
        let sessionsPoller = SessionsPollingUseCase(loader: sessionsLoader)
        let sessionProjectsLoader = SessionProjectsLoadUseCase(service: machinesService)
        let sessionProjectOpener = SessionProjectOpenUseCase(service: machinesService)
        let sessionProjectRemover = SessionProjectRemoveUseCase(service: machinesService)
        let directSessionMessagesLoader = DirectSessionMessagesLoadUseCase(
            codexService: machinesService,
            claudeService: machinesService,
            geminiService: machinesService
        )
        let directSessionCapabilitiesLoader = DirectSessionCapabilitiesLoadUseCase(service: machinesService)
        let directSessionMessageSender = DirectSessionMessageSendUseCase(
            codexService: machinesService,
            claudeService: machinesService,
            geminiService: machinesService
        )
        let directSessionFileLoader = DirectSessionFileLoadUseCase(service: machinesService)
        let directSessionReviewLoader = DirectSessionReviewLoadUseCase(service: machinesService)
        let directSessionWorktreeLoader = DirectSessionWorktreeLoadUseCase(service: machinesService)
        let sessionDeleteUseCase = SessionDeleteUseCase(service: sessionsService)
        self.onboarding = onboardingUseCase
        self.makeSettingsViewModel = { SettingsViewModel(settingsManager: settingsUseCase) }
        self.makeInboxViewModel = {
            InboxViewModel(
                loader: inboxLoader,
                friendAction: inboxFriendAction,
                userProfileLoader: inboxUserProfileLoader,
                userSearcher: inboxUserSearcher
            )
        }
        self.makeSessionsViewModel = {
            return SessionsViewModel(
                loader: sessionsLoader,
                pageLoader: sessionsPageLoader,
                poller: sessionsPoller,
                projectsLoader: sessionProjectsLoader,
                projectOpener: sessionProjectOpener,
                projectRemover: sessionProjectRemover,
                upstreamSessionsLoader: upstreamSessionsLoader,
                deleteUseCase: sessionDeleteUseCase
            )
        }
        self.makeNewSessionViewModel = {
            NewSessionViewModel(
                machinesLoader: newSessionMachinesLoader,
                directoryLister: newSessionDirectoryLister,
                spawner: newSessionSpawner,
                recentProjectsManager: newSessionRecentProjects,
                profilesManager: newSessionProfiles,
                modelsLoader: newSessionModelsLoader,
                codexThreadsLoader: newSessionCodexThreadsLoader,
                claudeSessionsLoader: newSessionClaudeSessionsLoader
            )
        }
        self.makeDirectSessionViewModel = { identity in
            DirectSessionViewModel(
                identity: identity,
                loader: directSessionMessagesLoader,
                sender: directSessionMessageSender,
                capabilitiesLoader: directSessionCapabilitiesLoader,
                fileLoader: directSessionFileLoader,
                reviewLoader: directSessionReviewLoader,
                worktreeLoader: directSessionWorktreeLoader
            )
        }
        self.makeMachinesViewModel = {
            MachinesViewModel(
                loader: machinesLoader,
                spawner: machineSpawner,
                updater: machineUpdater,
                stopper: machineStopper
            )
        }
        self.makeUsageViewModel = {
            UsageSettingsViewModel(usageLoader: usageLoader)
        }
        self.makeDaemonStatusViewModel = {
            ConnectorsDaemonStatusViewModel(loader: daemonStatusLoader)
        }
        self.makeTerminalConnectViewModel = {
            TerminalConnectSettingsViewModel(connector: terminalConnectUseCase)
        }
        self.makeAccountLinkViewModel = {
            AccountLinkSettingsViewModel(
                linker: accountLinkUseCase,
                restorer: accountRestoreUseCase,
                qrRestorer: accountRestoreQRUseCase,
                secretStore: accountSecretStore
            )
        }
        self.makeServerStatusViewModel = {
            HomeServerConnectionStatusViewModel(loader: homeServerStatusLoader)
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView(
                onboarding: onboarding,
                makeSettingsViewModel: makeSettingsViewModel,
                makeInboxViewModel: makeInboxViewModel,
                makeSessionsViewModel: makeSessionsViewModel,
                makeNewSessionViewModel: makeNewSessionViewModel,
                makeDirectSessionViewModel: makeDirectSessionViewModel,
                makeMachinesViewModel: makeMachinesViewModel,
                makeUsageViewModel: makeUsageViewModel,
                makeDaemonStatusViewModel: makeDaemonStatusViewModel,
                makeTerminalConnectViewModel: makeTerminalConnectViewModel,
                makeAccountLinkViewModel: makeAccountLinkViewModel,
                makeServerStatusViewModel: makeServerStatusViewModel
            )
            .preferredColorScheme(preferredColorScheme)
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch storedAppearanceMode {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }
}
