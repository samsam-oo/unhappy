import Foundation
import Testing
@testable import FeatureMachine
import CoreKit

@MainActor
struct MachinesViewModelTests {
    @Test
    func loadMachinesUsesReconnectStatusForTransientDataPlaneFailures() async {
        let viewModel = MachinesViewModel(
            loader: ReconnectingMachinesLoader(),
            spawner: NoopMachineSpawner(),
            updater: NoopMachineUpdater(),
            preventSleepSetter: NoopMachinePreventSleepSetter(),
            stopper: NoopMachineStopper(),
            deleter: NoopMachineDeleter()
        )

        await viewModel.loadMachines(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.reconnectingStatusText == "Reconnecting to machine…")
    }
}

private struct ReconnectingMachinesLoader: MachinesLoadingAction {
    func loadMachines(serverURLString: String, token: String) async throws -> [APIMachine] {
        throw MachinesAPIError.rpcTimedOut
    }
}

private struct NoopMachineSpawner: MachineSpawnAction {
    func spawnSession(_ request: MachineSpawnRequest) async throws -> APISessionSpawnResult {
        APISessionSpawnResult(
            success: true,
            sessionID: nil,
            requiresUserApproval: nil,
            actionRequired: nil,
            directory: nil,
            error: nil
        )
    }
}

private struct NoopMachineUpdater: MachineDaemonUpdateAction {
    func updateDaemon(serverURLString: String, token: String, machineID: String) async throws -> APIMachineCommandResult {
        APIMachineCommandResult(success: true, message: "updated", error: nil)
    }
}

private struct NoopMachineStopper: MachineDaemonStopAction {
    func stopDaemon(serverURLString: String, token: String, machineID: String) async throws -> APIMachineCommandResult {
        APIMachineCommandResult(success: true, message: "stopped", error: nil)
    }
}

private struct NoopMachinePreventSleepSetter: MachineDaemonPreventSleepAction {
    func setPreventSleep(
        serverURLString: String,
        token: String,
        machineID: String,
        enabled: Bool
    ) async throws -> APIMachineCommandResult {
        APIMachineCommandResult(success: true, message: enabled ? "enabled" : "disabled", error: nil)
    }
}

private struct NoopMachineDeleter: MachineDeleteAction {
    func deleteMachine(serverURLString: String, token: String, machineID: String) async throws -> APIMachineCommandResult {
        APIMachineCommandResult(success: true, message: "deleted", error: nil)
    }
}
