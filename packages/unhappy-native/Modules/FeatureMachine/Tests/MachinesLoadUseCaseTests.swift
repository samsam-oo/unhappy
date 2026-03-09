import Foundation
import Testing
@testable import FeatureMachine
import CoreKit

struct MachinesLoadUseCaseTests {
    @Test
    func loadMachinesThrowsMissingToken() async {
        let useCase = MachinesLoadUseCase(service: ImmediateMachinesService(machines: []))

        await #expect(throws: MachinesLoadError.missingToken) {
            _ = try await useCase.loadMachines(
                serverURLString: "https://api.unhappy.im",
                token: "   "
            )
        }
    }

    @Test
    func loadMachinesIncludesOfflineMachinesAfterOnlineMachines() async throws {
        let rows = [
            APIMachine(
                id: "offline",
                active: false,
                activeAt: 10,
                createdAt: 1,
                updatedAt: 10,
                metadataVersion: 1,
                metadata: "",
                daemonStateVersion: 0,
                daemonState: nil,
                dataEncryptionKey: nil
            ),
            APIMachine(
                id: "online",
                active: true,
                activeAt: 20,
                createdAt: 1,
                updatedAt: 20,
                metadataVersion: 1,
                metadata: "",
                daemonStateVersion: 0,
                daemonState: nil,
                dataEncryptionKey: nil
            )
        ]
        let useCase = MachinesLoadUseCase(service: ImmediateMachinesService(machines: rows))

        let loaded = try await useCase.loadMachines(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(loaded.map(\.id) == ["online", "offline"])
    }

    @Test
    func concurrentLoadsShareSingleInFlightRequest() async throws {
        let service = SlowCountingMachinesService(machines: [])
        let useCase = MachinesLoadUseCase(service: service)

        async let first = useCase.loadMachines(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )
        async let second = useCase.loadMachines(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        _ = try await first
        _ = try await second
        #expect(await service.fetchCount() == 1)
    }
}

private struct ImmediateMachinesService: MachinesFetching {
    let machines: [APIMachine]

    func fetchMachines(serverURL: URL, token: String) async throws -> [APIMachine] {
        machines
    }
}

private actor SlowCountingMachinesService: MachinesFetching {
    private let machines: [APIMachine]
    private var count: Int = 0

    init(machines: [APIMachine]) {
        self.machines = machines
    }

    func fetchMachines(serverURL: URL, token: String) async throws -> [APIMachine] {
        count += 1
        try await Task.sleep(nanoseconds: 80_000_000)
        return machines
    }

    func fetchCount() -> Int { count }
}
