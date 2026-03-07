import Testing
@testable import FeatureHome
import FeatureInbox
import FeatureSessions
import FeatureSessionTools
import FeatureMachine
import FeatureNewSession
import CoreKit
import FeatureSettings

@MainActor
struct FeatureHomeTests {
    @Test
    func homeViewCanInitialize() {
        _ = HomeView(
            onboarding: MockHomeAccountOnboarding(),
            makeSettingsViewModel: {
                SettingsViewModel(settingsManager: MockSettingsManager())
            },
            makeInboxViewModel: {
                InboxViewModel(loader: MockInboxLoader())
            },
            makeSessionsViewModel: {
                SessionsViewModel(service: URLSessionSessionsService())
            },
            makeNewSessionViewModel: {
                let service = URLSessionMachinesService()
                return NewSessionViewModel(
                    machinesLoader: NewSessionMachinesLoadUseCase(service: service),
                    directoryLister: NewSessionDirectoryListUseCase(service: service),
                    spawner: NewSessionSpawnUseCase(service: service),
                    recentProjectsManager: NewSessionNoopRecentProjectsManager(),
                    profilesManager: NewSessionNoopProfilesManager(),
                    modelsLoader: NewSessionModelsLoadUseCase(service: service)
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
                    loader: MockHomeServerStatusLoader(status: .connected)
                )
            }
        )
    }

    @Test
    func regularProjectsSelectionReducerDoesNotAutoSelectFirstProject() {
        #expect(
            HomeRegularProjectsSelectionState.retainedSelectionID(
                currentSelectionID: nil,
                availableProjectIDs: ["project-1", "project-2"]
            ) == nil
        )
    }
}

private actor MockSettingsManager: SettingsManaging {
    func loadSettings() async -> AppSettingsSnapshot {
        AppSettingsSnapshot(serverURLString: "https://api.unhappy.im", apiToken: "")
    }

    func persistSettings(_ snapshot: AppSettingsSnapshot) async {}
}

private actor MockHomeAccountOnboarding: HomeAccountOnboardingAction {
    func createAccount(serverURLString: String) async throws -> String {
        "token"
    }
}

private struct MockHomeServerStatusLoader: HomeServerConnectionStatusLoadingAction {
    let status: HomeServerConnectionStatus

    func loadStatus(serverURLString: String) async -> HomeServerConnectionStatus {
        status
    }
}

private actor MockInboxLoader: InboxLoadingAction {
    func loadInboxSnapshot(serverURLString: String, token: String) async throws -> InboxSnapshot {
        InboxSnapshot(feedItems: [], friendRequests: [], requestedFriends: [], friends: [])
    }
}
