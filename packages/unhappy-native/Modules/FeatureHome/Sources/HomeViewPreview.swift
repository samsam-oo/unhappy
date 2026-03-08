import SwiftUI
import CoreKit
import FeatureInbox
import FeatureMachine
import FeatureNewSession
import FeatureSessions
import FeatureSessionTools
import FeatureSettings

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
                profilesManager: NewSessionNoopProfilesManager(),
                modelsLoader: NewSessionModelsLoadUseCase(service: service),
                codexThreadsLoader: NewSessionCodexThreadsLoadUseCase(service: service),
                claudeSessionsLoader: NewSessionClaudeSessionsLoadUseCase(service: service)
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
        makeCodexDirectSessionViewModel: { identity in
            let service = URLSessionMachinesService()
            return CodexDirectSessionViewModel(
                identity: identity,
                loader: CodexDirectSessionMessagesLoadUseCase(service: service),
                sender: CodexDirectSessionMessageSendUseCase(service: service)
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
