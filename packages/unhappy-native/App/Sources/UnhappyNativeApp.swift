import SwiftUI
import CoreKit
import FeatureHome
import FeatureMachine
import FeatureNewSession
import FeatureSessions
import FeatureSessionTools
import FeatureSettings

@main
struct UnhappyNativeApp: App {
    private let makeSettingsViewModel: @MainActor () -> SettingsViewModel
    private let makeSessionsViewModel: @MainActor () -> SessionsViewModel
    private let makeNewSessionViewModel: @MainActor () -> NewSessionViewModel
    private let makeSessionToolsViewModel: @MainActor () -> SessionToolsViewModel
    private let makeMachinesViewModel: @MainActor () -> MachinesViewModel
    private let makeUsageViewModel: @MainActor () -> UsageSettingsViewModel
    private let makeDaemonStatusViewModel: @MainActor () -> ConnectorsDaemonStatusViewModel

    init() {
        let settingsStore = UserDefaultsAppSettingsStore()
        let settingsUseCase = SettingsUseCase(store: settingsStore)
        let sessionsService = URLSessionSessionsService()
        let machinesService = URLSessionMachinesService()
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
        let newSessionRecentProjects = NewSessionRecentProjectsUseCase(store: settingsStore)
        let newSessionProfiles = NewSessionProfilesUseCase(store: UserDefaultsNewSessionProfilesStore())
        let usageLoader = SettingsUsageLoadUseCase(service: sessionsService)
        let daemonStatusLoader = DaemonStatusLoadUseCase(service: machinesService)
        self.makeSettingsViewModel = { SettingsViewModel(settingsManager: settingsUseCase) }
        self.makeSessionsViewModel = { SessionsViewModel(service: sessionsService) }
        self.makeNewSessionViewModel = {
            NewSessionViewModel(
                machinesLoader: newSessionMachinesLoader,
                directoryLister: newSessionDirectoryLister,
                spawner: newSessionSpawner,
                recentProjectsManager: newSessionRecentProjects,
                profilesManager: newSessionProfiles
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
    }

    var body: some Scene {
        WindowGroup {
            HomeView(
                makeSettingsViewModel: makeSettingsViewModel,
                makeSessionsViewModel: makeSessionsViewModel,
                makeNewSessionViewModel: makeNewSessionViewModel,
                makeSessionToolsViewModel: makeSessionToolsViewModel,
                makeMachinesViewModel: makeMachinesViewModel,
                makeUsageViewModel: makeUsageViewModel,
                makeDaemonStatusViewModel: makeDaemonStatusViewModel
            )
        }
    }
}
