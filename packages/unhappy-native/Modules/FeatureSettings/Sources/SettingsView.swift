import SwiftUI
import CoreKit
import FeatureMachine

@MainActor
public struct SettingsView: View {
    @ObservedObject private var viewModel: SettingsViewModel
    private let makeMachinesViewModel: @MainActor () -> MachinesViewModel
    private let makeUsageViewModel: @MainActor () -> UsageSettingsViewModel

    public init(
        viewModel: SettingsViewModel,
        makeMachinesViewModel: @escaping @MainActor () -> MachinesViewModel,
        makeUsageViewModel: @escaping @MainActor () -> UsageSettingsViewModel
    ) {
        self.viewModel = viewModel
        self.makeMachinesViewModel = makeMachinesViewModel
        self.makeUsageViewModel = makeUsageViewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    NavigationLink {
                        AccountSettingsView(viewModel: viewModel)
                    } label: {
                        Label("Account", systemImage: "person.crop.circle")
                    }
                    NavigationLink {
                        ServerSettingsView(viewModel: viewModel)
                    } label: {
                        Label("Server", systemImage: "server.rack")
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
                        UsageSettingsView(
                            serverURLString: viewModel.serverURLString,
                            token: viewModel.apiToken,
                            makeViewModel: makeUsageViewModel
                        )
                    } label: {
                        Label("Usage", systemImage: "chart.bar.xaxis")
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
            .navigationTitle("Settings")
        }
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
        useEnhancedSessionWizard: Bool
    ) async {}
}
