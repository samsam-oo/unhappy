import SwiftUI
import CoreKit
import FeatureMachine
import FeatureNewSession
import FeatureSessions
import FeatureSessionTools
import FeatureSettings

@MainActor
public struct HomeView: View {
    @StateObject private var settingsViewModel: SettingsViewModel
    private let makeSessionsViewModel: @MainActor () -> SessionsViewModel
    private let makeNewSessionViewModel: @MainActor () -> NewSessionViewModel
    private let makeSessionToolsViewModel: @MainActor () -> SessionToolsViewModel
    private let makeMachinesViewModel: @MainActor () -> MachinesViewModel

    public init(
        makeSettingsViewModel: @escaping @MainActor () -> SettingsViewModel,
        makeSessionsViewModel: @escaping @MainActor () -> SessionsViewModel,
        makeNewSessionViewModel: @escaping @MainActor () -> NewSessionViewModel,
        makeSessionToolsViewModel: @escaping @MainActor () -> SessionToolsViewModel,
        makeMachinesViewModel: @escaping @MainActor () -> MachinesViewModel
    ) {
        _settingsViewModel = StateObject(wrappedValue: makeSettingsViewModel())
        self.makeSessionsViewModel = makeSessionsViewModel
        self.makeNewSessionViewModel = makeNewSessionViewModel
        self.makeSessionToolsViewModel = makeSessionToolsViewModel
        self.makeMachinesViewModel = makeMachinesViewModel
    }

    public var body: some View {
        TabView {
            SessionsView(
                serverURLString: settingsViewModel.serverURLString,
                token: settingsViewModel.apiToken,
                makeViewModel: makeSessionsViewModel,
                makeNewSessionViewModel: makeNewSessionViewModel,
                makeSessionToolsViewModel: makeSessionToolsViewModel
            )
                .tabItem {
                    Label("Sessions", systemImage: "bubble.left.and.bubble.right")
                }

            SettingsView(
                viewModel: settingsViewModel,
                makeMachinesViewModel: makeMachinesViewModel
            )
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .task {
            await settingsViewModel.loadFromStore()
        }
    }
}

#Preview {
    HomeView(
        makeSettingsViewModel: {
            SettingsViewModel(
                settingsManager: SettingsUseCase(store: UserDefaultsAppSettingsStore())
            )
        },
        makeSessionsViewModel: { SessionsViewModel(service: URLSessionSessionsService()) },
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
