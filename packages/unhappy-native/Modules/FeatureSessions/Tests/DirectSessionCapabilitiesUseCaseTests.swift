import Foundation
import Testing
import CoreKit
import SessionKit

struct DirectSessionCapabilitiesUseCaseTests {
    @Test
    func loadCapabilitiesCachesRepeatedRequests() async throws {
        let service = CapabilitiesListingService(
            capabilities: APIMachineAgentCapabilities(
                models: ["gpt-5-codex"],
                reasoningEfforts: ["medium"]
            ),
            delayNanoseconds: 0
        )
        let useCase = DirectSessionCapabilitiesLoadUseCase(service: service)
        let identity = DirectSessionIdentity(
            machineID: "machine-1",
            machineDisplayName: "Mac",
            wrappedMachineDataEncryptionKey: nil,
            provider: .codex,
            upstreamSessionID: "thread-1",
            title: "Codex",
            cwd: "/repo",
            transcriptPath: "/repo/.codex/transcript.jsonl",
            model: "gpt-5-codex",
            effort: nil,
            permissionMode: nil,
            collabInProgressCount: 0
        )

        let first = try await useCase.loadCapabilities(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            identity: identity
        )
        let second = try await useCase.loadCapabilities(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            identity: identity
        )

        #expect(first == second)
        #expect(await service.callCount == 1)
    }

    @Test
    func loadCapabilitiesSharesInFlightRequests() async throws {
        let service = CapabilitiesListingService(
            capabilities: APIMachineAgentCapabilities(
                models: ["claude-sonnet-4-5"],
                reasoningEfforts: ["high"]
            ),
            delayNanoseconds: 50_000_000
        )
        let useCase = DirectSessionCapabilitiesLoadUseCase(service: service)
        let identity = DirectSessionIdentity(
            machineID: "machine-1",
            machineDisplayName: "Mac",
            wrappedMachineDataEncryptionKey: nil,
            provider: .claude,
            upstreamSessionID: "session-1",
            title: "Claude",
            cwd: "/repo",
            transcriptPath: nil,
            model: "claude-sonnet-4-5",
            effort: nil,
            permissionMode: nil,
            collabInProgressCount: 0
        )

        async let first = useCase.loadCapabilities(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            identity: identity
        )
        async let second = useCase.loadCapabilities(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            identity: identity
        )

        let results = try await [first, second]

        #expect(results[0] == results[1])
        #expect(await service.callCount == 1)
    }
}

private actor CapabilitiesListingService: MachineModelsListing {
    let capabilities: APIMachineAgentCapabilities
    let delayNanoseconds: UInt64
    private(set) var callCount = 0

    init(capabilities: APIMachineAgentCapabilities, delayNanoseconds: UInt64) {
        self.capabilities = capabilities
        self.delayNanoseconds = delayNanoseconds
    }

    func fetchAgentCapabilities(
        serverURL: URL,
        token: String,
        machineID: String,
        agent: APISessionSpawnAgent
    ) async throws -> APIMachineAgentCapabilities {
        callCount += 1
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return capabilities
    }
}
