import Testing
@testable import FeatureHome
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
            makeSettingsViewModel: {
                SettingsViewModel(settingsManager: MockSettingsManager())
            },
            makeSessionsViewModel: {
                SessionsViewModel(service: URLSessionSessionsService())
            },
            makeNewSessionViewModel: {
                let service = URLSessionMachinesService()
                return NewSessionViewModel(
                    machinesLoader: NewSessionMachinesLoadUseCase(service: service),
                    directoryLister: NewSessionDirectoryListUseCase(service: service),
                    spawner: NewSessionSpawnUseCase(service: service)
                )
            },
            makeSessionToolsViewModel: {
                let service = URLSessionSessionsService()
                return SessionToolsViewModel(
                    fileLoader: SessionFileLoadUseCase(service: service),
                    directoryLister: SessionDirectoryListUseCase(service: service),
                    fileWriter: SessionFileWriteUseCase(service: service),
                    killer: SessionKillUseCase(service: service),
                    aborter: SessionTaskAbortUseCase(service: service),
                    permissionResponder: SessionPermissionUseCase(service: service),
                    modeSwitcher: SessionModeSwitchUseCase(service: service)
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
            }
        )
    }
}

private actor MockSettingsManager: SettingsManaging {
    func loadSettings() async -> AppSettingsSnapshot {
        AppSettingsSnapshot(serverURLString: "https://api.unhappy.im", apiToken: "")
    }

    func persistSettings(serverURLString: String, apiToken: String) async {}
}
