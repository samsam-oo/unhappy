import SwiftUI
import CoreKit
import FeatureMachine

@MainActor
public struct SettingsView: View {
    @ObservedObject private var viewModel: SettingsViewModel
    private let makeMachinesViewModel: @MainActor () -> MachinesViewModel

    public init(
        viewModel: SettingsViewModel,
        makeMachinesViewModel: @escaping @MainActor () -> MachinesViewModel
    ) {
        self.viewModel = viewModel
        self.makeMachinesViewModel = makeMachinesViewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("API") {
                    TextField("Server URL", text: $viewModel.serverURLString)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("API Token", text: $viewModel.apiToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Notes") {
                    Text("This app uses direct native API calls.")
                        .foregroundStyle(.secondary)
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
        }
    )
}

private actor PreviewSettingsManager: SettingsManaging {
    func loadSettings() async -> AppSettingsSnapshot {
        AppSettingsSnapshot(serverURLString: "https://api.unhappy.im", apiToken: "")
    }

    func persistSettings(serverURLString: String, apiToken: String) async {}
}
