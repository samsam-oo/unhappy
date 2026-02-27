import SwiftUI
import CoreKit
import FeatureHome
import FeatureInbox
import FeatureMachine
import FeatureNewSession
import FeatureSessions
import FeatureSessionTools
import FeatureSettings

@main
struct UnhappyNativeApp: App {
    private let onboarding: any HomeAccountOnboardingAction
    private let makeSettingsViewModel: @MainActor () -> SettingsViewModel
    private let makeInboxViewModel: @MainActor () -> InboxViewModel
    private let makeSessionsViewModel: @MainActor () -> SessionsViewModel
    private let makeNewSessionViewModel: @MainActor () -> NewSessionViewModel
    private let makeSessionToolsViewModel: @MainActor () -> SessionToolsViewModel
    private let sessionPresenceCoordinator: any SessionPresenceCoordinating
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
        let sessionFileLoader = SessionFileLoadUseCase(service: sessionsService)
        let sessionDirectoryLister = SessionDirectoryListUseCase(service: sessionsService)
        let sessionFileWriter = SessionFileWriteUseCase(service: sessionsService)
        let sessionKiller = SessionKillUseCase(service: sessionsService)
        let sessionAborter = SessionTaskAbortUseCase(service: sessionsService)
        let sessionPermissionResponder = SessionPermissionUseCase(service: sessionsService)
        let sessionModeSwitcher = SessionModeSwitchUseCase(service: sessionsService)
        let sessionBasher = SessionBashUseCase(service: sessionsService)
        let sessionFileDiffPreviewer = SessionFileDiffPreviewUseCase(basher: sessionBasher)
        let sessionRipgrepRunner = SessionRipgrepUseCase(service: sessionsService)
        let sessionDifftasticRunner = SessionDifftasticUseCase(service: sessionsService)
        let machinesLoader = MachinesLoadUseCase(service: machinesService)
        let machineSpawner = MachineSpawnUseCase(service: machinesService)
        let machineUpdater = MachineDaemonUpdateUseCase(service: machinesService)
        let machineStopper = MachineDaemonStopUseCase(service: machinesService)
        let newSessionMachinesLoader = NewSessionMachinesLoadUseCase(service: machinesService)
        let newSessionDirectoryLister = NewSessionDirectoryListUseCase(service: machinesService)
        let newSessionSpawner = NewSessionSpawnUseCase(service: machinesService)
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
        let sessionsNotifier = UserNotificationsSessionNotifier()
        let sessionsLiveActivity = ActivityKitSessionsLiveActivityService()
        let sessionPresenceCoordinator = SessionPresenceCoordinator(
            notifications: sessionsNotifier,
            liveActivity: sessionsLiveActivity
        )
        self.onboarding = onboardingUseCase
        self.sessionPresenceCoordinator = sessionPresenceCoordinator
        self.makeSettingsViewModel = { SettingsViewModel(settingsManager: settingsUseCase) }
        self.makeInboxViewModel = {
            InboxViewModel(
                loader: inboxLoader,
                friendAction: inboxFriendAction,
                userProfileLoader: inboxUserProfileLoader,
                userSearcher: inboxUserSearcher
            )
        }
        self.makeSessionsViewModel = { SessionsViewModel(service: sessionsService) }
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
        self.makeSessionToolsViewModel = {
            SessionToolsViewModel(
                fileLoader: sessionFileLoader,
                directoryLister: sessionDirectoryLister,
                fileWriter: sessionFileWriter,
                fileDiffPreviewer: sessionFileDiffPreviewer,
                killer: sessionKiller,
                aborter: sessionAborter,
                permissionResponder: sessionPermissionResponder,
                modeSwitcher: sessionModeSwitcher,
                basher: sessionBasher,
                ripgrepRunner: sessionRipgrepRunner,
                difftasticRunner: sessionDifftasticRunner
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
                makeSessionToolsViewModel: makeSessionToolsViewModel,
                onSessionsChanged: { sessions in
                    await sessionPresenceCoordinator.handleSessionsChanged(sessions)
                },
                makeMachinesViewModel: makeMachinesViewModel,
                makeUsageViewModel: makeUsageViewModel,
                makeDaemonStatusViewModel: makeDaemonStatusViewModel,
                makeTerminalConnectViewModel: makeTerminalConnectViewModel,
                makeAccountLinkViewModel: makeAccountLinkViewModel,
                makeServerStatusViewModel: makeServerStatusViewModel
            )
            .task {
                await sessionPresenceCoordinator.start()
            }
        }
    }
}
