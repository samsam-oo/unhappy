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
                approvedNewDirectoryCreation: false,
                codexResumeThreadID: nil,
                claudeResumeSessionID: nil,
                sessionToken: nil,
                environmentVariables: [:]
            )
        }
    }

    @Test
    func spawnForwardsResumeTokenAndEnvironment() async throws {
        let service = SpawnService(
            response: APISessionSpawnResult(
                success: true,
                sessionID: "s-1",
                requiresUserApproval: nil,
                actionRequired: nil,
                directory: nil,
                error: nil
            )
        )
        let useCase = NewSessionSpawnUseCase(service: service)
        _ = try await useCase.spawnSession(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            machineID: "machine-1",
            directory: "/repo",
            agent: .codex,
            approvedNewDirectoryCreation: true,
            codexResumeThreadID: "thread-123",
            claudeResumeSessionID: "claude-456",
            sessionToken: "session-token",
            environmentVariables: ["OPENAI_API_KEY": "test-key"]
        )

        let request = await service.lastRequest
        #expect(request?.machineID == "machine-1")
        #expect(request?.directory == "/repo")
        #expect(request?.agent == .codex)
        #expect(request?.approvedNewDirectoryCreation == true)
        #expect(request?.codexResumeThreadID == "thread-123")
        #expect(request?.claudeResumeSessionID == "claude-456")
        #expect(request?.sessionToken == "session-token")
        #expect(request?.environmentVariables == ["OPENAI_API_KEY": "test-key"])
    }

    @Test
    func recentProjectsUseCaseDeduplicatesAndCapsList() async {
        let suiteName = "im.unhappy.newsession.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("failed to create UserDefaults test suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let useCase = NewSessionRecentProjectsUseCase(store: store, maxProjects: 3)
        _ = await useCase.recordRecentProject("/repo/a")
        _ = await useCase.recordRecentProject("/repo/b")
        _ = await useCase.recordRecentProject("/repo/c")
        _ = await useCase.recordRecentProject("/repo/b")
        _ = await useCase.recordRecentProject("/repo/d")

        #expect(await useCase.loadRecentProjects() == ["/repo/d", "/repo/b", "/repo/c"])
    }

    @Test
    func recentProjectsUseCaseIgnoresEmptyPath() async {
        let suiteName = "im.unhappy.newsession.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("failed to create UserDefaults test suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let useCase = NewSessionRecentProjectsUseCase(store: store, maxProjects: 3)
        _ = await useCase.recordRecentProject("/repo/a")
        let updated = await useCase.recordRecentProject("   ")

        #expect(updated == ["/repo/a"])
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

private struct SpawnRequest: Equatable {
    let machineID: String
    let directory: String
    let agent: APISessionSpawnAgent?
    let codexResumeThreadID: String?
    let claudeResumeSessionID: String?
    let approvedNewDirectoryCreation: Bool?
    let sessionToken: String?
    let environmentVariables: [String: String]?
}

private actor SpawnService: MachineSessionSpawning {
    let response: APISessionSpawnResult
    var lastRequest: SpawnRequest?

    init(response: APISessionSpawnResult) {
        self.response = response
        self.lastRequest = nil
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
        environmentVariables: [String : String]?
    ) async throws -> APISessionSpawnResult {
        lastRequest = SpawnRequest(
            machineID: machineID,
            directory: directory,
            agent: agent,
            codexResumeThreadID: codexResumeThreadID,
            claudeResumeSessionID: claudeResumeSessionID,
            approvedNewDirectoryCreation: approvedNewDirectoryCreation,
            sessionToken: sessionToken,
            environmentVariables: environmentVariables
        )
        return response
    }
}
