import Foundation
import Testing
@testable import FeatureMachine
import CoreKit

struct MachineSpawnUseCaseTests {
    @Test
    func spawnThrowsMissingDirectory() async {
        let useCase = MachineSpawnUseCase(service: ImmediateMachineSpawnService(response: .init(success: true, sessionID: nil, requiresUserApproval: nil, actionRequired: nil, directory: nil, error: nil)))

        await #expect(throws: MachineSpawnError.missingDirectory) {
            _ = try await useCase.spawnSession(
                serverURLString: "https://api.unhappy.im",
                token: "token",
                machineID: "machine-1",
                directory: " ",
                agent: .claude,
                approvedNewDirectoryCreation: false
            )
        }
    }

    @Test
    func spawnThrowsApprovalWhenServerRequiresIt() async {
        let response = APISessionSpawnResult(
            success: false,
            sessionID: nil,
            requiresUserApproval: true,
            actionRequired: "CREATE_DIRECTORY",
            directory: "/tmp/new",
            error: nil
        )
        let useCase = MachineSpawnUseCase(service: ImmediateMachineSpawnService(response: response))

        await #expect(throws: MachineSpawnError.requiresUserApproval(directory: "/tmp/new")) {
            _ = try await useCase.spawnSession(
                serverURLString: "https://api.unhappy.im",
                token: "token",
                machineID: "machine-1",
                directory: "/tmp/new",
                agent: .claude,
                approvedNewDirectoryCreation: false
            )
        }
    }

    @Test
    func concurrentSpawnsShareSingleInFlightRequest() async throws {
        let response = APISessionSpawnResult(
            success: true,
            sessionID: "session-new",
            requiresUserApproval: nil,
            actionRequired: nil,
            directory: nil,
            error: nil
        )
        let service = SlowCountingMachineSpawnService(response: response)
        let useCase = MachineSpawnUseCase(service: service)

        async let first = useCase.spawnSession(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            machineID: "machine-1",
            directory: "/tmp/work",
            agent: .codex,
            approvedNewDirectoryCreation: false
        )
        async let second = useCase.spawnSession(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            machineID: "machine-1",
            directory: "/tmp/work",
            agent: .codex,
            approvedNewDirectoryCreation: false
        )

        let a = try await first
        let b = try await second
        #expect(a.sessionID == "session-new")
        #expect(b.sessionID == "session-new")
        #expect(await service.fetchCount() == 1)
    }
}

private struct ImmediateMachineSpawnService: MachineSessionSpawning {
    let response: APISessionSpawnResult

    func spawnSession(
        serverURL: URL,
        token: String,
        machineID: String,
        directory: String,
        agent: APISessionSpawnAgent?,
        codexResumeThreadID: String?,
        claudeResumeSessionID: String?,
        approvedNewDirectoryCreation: Bool?,
        sessionToken: String?,
        environmentVariables: [String : String]?,
        model: String?,
        reasoningEffort: APISessionReasoningEffort?
    ) async throws -> APISessionSpawnResult {
        response
    }
}

private actor SlowCountingMachineSpawnService: MachineSessionSpawning {
    private let response: APISessionSpawnResult
    private var count: Int = 0

    init(response: APISessionSpawnResult) {
        self.response = response
    }

    func spawnSession(
        serverURL: URL,
        token: String,
        machineID: String,
        directory: String,
        agent: APISessionSpawnAgent?,
        codexResumeThreadID: String?,
        claudeResumeSessionID: String?,
        approvedNewDirectoryCreation: Bool?,
        sessionToken: String?,
        environmentVariables: [String : String]?,
        model: String?,
        reasoningEffort: APISessionReasoningEffort?
    ) async throws -> APISessionSpawnResult {
        count += 1
        try await Task.sleep(nanoseconds: 80_000_000)
        return response
    }

    func fetchCount() -> Int { count }
}
