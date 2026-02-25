import Foundation
import Testing
import CoreKit
@testable import FeatureNewSession

struct NewSessionUseCasesTests {
    @Test
    func loadMachinesSortsActiveFirst() async throws {
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
        let useCase = NewSessionMachinesLoadUseCase(service: MachinesService(machines: rows))

        let loaded = try await useCase.loadMachines(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(loaded.map(\.id) == ["online", "offline"])
    }

    @Test
    func listDirectorySortsDirectoriesFirst() async throws {
        let entries = [
            APIMachineDirectoryEntry(name: "z.swift", type: "file", size: nil, modified: nil),
            APIMachineDirectoryEntry(name: "Sources", type: "directory", size: nil, modified: nil),
            APIMachineDirectoryEntry(name: "App", type: "directory", size: nil, modified: nil),
        ]
        let useCase = NewSessionDirectoryListUseCase(
            service: DirectoryService(
                result: APIMachineListDirectoryResult(success: true, entries: entries, error: nil)
            )
        )

        let loaded = try await useCase.listDirectory(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            machineID: "machine-1",
            path: "/repo"
        )

        #expect(loaded.map(\.name) == ["App", "Sources", "z.swift"])
    }

    @Test
    func spawnThrowsApprovalError() async {
        let response = APISessionSpawnResult(
            success: false,
            sessionID: nil,
            requiresUserApproval: true,
            actionRequired: "CREATE_DIRECTORY",
            directory: "/tmp/new",
            error: nil
        )
        let useCase = NewSessionSpawnUseCase(service: SpawnService(response: response))

        await #expect(throws: NewSessionError.requiresUserApproval(directory: "/tmp/new")) {
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
}

private struct MachinesService: MachinesFetching {
    let machines: [APIMachine]

    func fetchMachines(serverURL: URL, token: String) async throws -> [APIMachine] {
        machines
    }
}

private struct DirectoryService: MachineDirectoryListing {
    let result: APIMachineListDirectoryResult

    func listDirectory(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String
    ) async throws -> APIMachineListDirectoryResult {
        result
    }
}

private struct SpawnService: MachineSessionSpawning {
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
        environmentVariables: [String : String]?
    ) async throws -> APISessionSpawnResult {
        response
    }
}
