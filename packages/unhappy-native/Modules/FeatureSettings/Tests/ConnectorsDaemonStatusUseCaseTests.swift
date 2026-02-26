import Foundation
import Testing
import CoreKit
@testable import FeatureSettings

struct ConnectorsDaemonStatusUseCaseTests {
    @Test
    func loadStatusAggregatesMachineCounts() async throws {
        let machines = [
            APIMachine(
                id: "m1",
                active: true,
                activeAt: 10,
                createdAt: 1,
                updatedAt: 10,
                metadataVersion: 1,
                metadata: "",
                daemonStateVersion: 1,
                daemonState: #"{"running":true}"#,
                dataEncryptionKey: nil
            ),
            APIMachine(
                id: "m2",
                active: false,
                activeAt: 0,
                createdAt: 1,
                updatedAt: 9,
                metadataVersion: 1,
                metadata: "",
                daemonStateVersion: 0,
                daemonState: nil,
                dataEncryptionKey: nil
            )
        ]
        let useCase = DaemonStatusLoadUseCase(service: MachinesService(machines: machines))

        let snapshot = try await useCase.loadStatus(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(snapshot.totalMachines == 2)
        #expect(snapshot.onlineMachines == 1)
        #expect(snapshot.daemonStateMachines == 1)
        #expect(snapshot.isReady == true)
    }

    @Test
    func loadStatusThrowsMissingToken() async {
        let useCase = DaemonStatusLoadUseCase(service: MachinesService(machines: []))

        await #expect(throws: DaemonStatusError.missingToken) {
            _ = try await useCase.loadStatus(
                serverURLString: "https://api.unhappy.im",
                token: "   "
            )
        }
    }

    @Test
    func loadStatusThrowsInvalidURL() async {
        let useCase = DaemonStatusLoadUseCase(service: MachinesService(machines: []))

        await #expect(throws: DaemonStatusError.invalidServerURL) {
            _ = try await useCase.loadStatus(
                serverURLString: "not-a-url",
                token: "token"
            )
        }
    }
}

private struct MachinesService: MachinesFetching {
    let machines: [APIMachine]

    func fetchMachines(serverURL: URL, token: String) async throws -> [APIMachine] {
        machines
    }
}
