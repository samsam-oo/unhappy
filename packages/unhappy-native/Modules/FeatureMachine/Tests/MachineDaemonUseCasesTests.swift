import Foundation
import Testing
@testable import FeatureMachine
import CoreKit

struct MachineDaemonUseCasesTests {
    @Test
    func updateDaemonReturnsMessage() async throws {
        let useCase = MachineDaemonUpdateUseCase(
            service: DaemonUpdateService(result: .init(success: true, message: "updated", error: nil))
        )

        let result = try await useCase.updateDaemon(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            machineID: "machine-1"
        )

        #expect(result.message == "updated")
    }

    @Test
    func stopDaemonThrowsWhenResultIsFailure() async {
        let useCase = MachineDaemonStopUseCase(
            service: DaemonStopService(result: .init(success: false, message: "failed", error: "offline"))
        )

        await #expect(throws: MachineDaemonError.failed(message: "offline")) {
            _ = try await useCase.stopDaemon(
                serverURLString: "https://api.unhappy.im",
                token: "token",
                machineID: "machine-1"
            )
        }
    }

    @Test
    func setPreventSleepReturnsMessage() async throws {
        let useCase = MachineDaemonPreventSleepUseCase(
            service: DaemonPreventSleepService(result: .init(success: true, message: "enabled", error: nil))
        )

        let result = try await useCase.setPreventSleep(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            machineID: "machine-1",
            enabled: true
        )

        #expect(result.message == "enabled")
    }

    @Test
    func deleteMachineReturnsMessage() async throws {
        let useCase = MachineDeleteUseCase(
            service: MachineDeleteService(result: .init(success: true, message: "deleted", error: nil))
        )

        let result = try await useCase.deleteMachine(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            machineID: "machine-1"
        )

        #expect(result.message == "deleted")
    }
}

private struct DaemonUpdateService: MachineDaemonUpdating {
    let result: APIMachineCommandResult

    func updateDaemon(serverURL: URL, token: String, machineID: String) async throws -> APIMachineCommandResult {
        result
    }
}

private struct DaemonStopService: MachineDaemonStopping {
    let result: APIMachineCommandResult

    func stopDaemon(serverURL: URL, token: String, machineID: String) async throws -> APIMachineCommandResult {
        result
    }
}

private struct DaemonPreventSleepService: MachineDaemonPreventSleepSetting {
    let result: APIMachineCommandResult

    func setDaemonPreventSleep(
        serverURL: URL,
        token: String,
        machineID: String,
        enabled: Bool
    ) async throws -> APIMachineCommandResult {
        result
    }
}

private struct MachineDeleteService: MachineDeleting {
    let result: APIMachineCommandResult

    func deleteMachine(serverURL: URL, token: String, machineID: String) async throws -> APIMachineCommandResult {
        result
    }
}
