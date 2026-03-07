import Foundation
import Testing
import CoreKit
@testable import FeatureNewSession

struct NewSessionUseCasesTests {
    @Test
    func loadMachinesIncludesOnlyActiveMachines() async throws {
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

        #expect(loaded.map(\.id) == ["online"])
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
    func loadCodexThreadsForwardsMachineAndPath() async throws {
        let expected = APICodexThreadsPage(
            threads: [
                APICodexThreadSummary(
                    id: "thread-1",
                    name: "Bugfix",
                    cwd: "/repo",
                    updatedAt: "2026-02-24T10:00:00.000Z",
                    createdAt: "2026-02-24T09:00:00.000Z",
                    archived: false
                )
            ],
            nextCursor: "next-cursor",
            hasNext: true
        )
        let service = CodexThreadsService(page: expected)
        let useCase = NewSessionCodexThreadsLoadUseCase(service: service)

        let page = try await useCase.loadCodexThreads(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            machineID: "machine-1",
            limit: 20,
            cwd: "/repo",
            cursor: nil
        )

        let request = await service.lastRequest
        #expect(page == expected)
        #expect(request?.machineID == "machine-1")
        #expect(request?.cwd == "/repo")
        #expect(request?.cursor == nil)
    }

    @Test
    func loadClaudeSessionsForwardsMachineAndPath() async throws {
        let expected = APIClaudeSessionsPage(
            sessions: [
                APIClaudeSessionSummary(
                    id: "c7a2f5d1-1111-2222-3333-444444444444",
                    cwd: "/repo",
                    updatedAt: "2026-02-24T10:00:00.000Z",
                    createdAt: "2026-02-24T09:00:00.000Z"
                )
            ],
            nextCursor: "next-cursor",
            hasNext: true
        )
        let service = ClaudeSessionsService(page: expected)
        let useCase = NewSessionClaudeSessionsLoadUseCase(service: service)

        let page = try await useCase.loadClaudeSessions(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            machineID: "machine-1",
            limit: 20,
            cwd: "/repo",
            cursor: nil
        )

        let request = await service.lastRequest
        #expect(page == expected)
        #expect(request?.machineID == "machine-1")
        #expect(request?.cwd == "/repo")
        #expect(request?.cursor == nil)
    }

    @Test
    func loadCodexThreadsForwardsCursor() async throws {
        let service = CodexThreadsService(
            page: APICodexThreadsPage(threads: [], nextCursor: nil, hasNext: false)
        )
        let useCase = NewSessionCodexThreadsLoadUseCase(service: service)

        _ = try await useCase.loadCodexThreads(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            machineID: "machine-1",
            limit: 20,
            cwd: "/repo",
            cursor: "cursor-20"
        )

        let request = await service.lastRequest
        #expect(request?.cursor == "cursor-20")
    }

    @Test
    func loadClaudeSessionsForwardsCursor() async throws {
        let service = ClaudeSessionsService(
            page: APIClaudeSessionsPage(sessions: [], nextCursor: nil, hasNext: false)
        )
        let useCase = NewSessionClaudeSessionsLoadUseCase(service: service)

        _ = try await useCase.loadClaudeSessions(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            machineID: "machine-1",
            limit: 20,
            cwd: "/repo",
            cursor: "cursor-12"
        )

        let request = await service.lastRequest
        #expect(request?.cursor == "cursor-12")
    }

    @Test
    func loadModelsForwardsMachineAndAgent() async throws {
        let service = ModelsService(models: ["gpt-5", "gpt-5-codex"])
        let useCase = NewSessionModelsLoadUseCase(service: service)

        let capabilities = try await useCase.loadModels(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            machineID: "machine-1",
            agent: .codex
        )

        let request = await service.lastRequest
        #expect(capabilities.models == ["gpt-5", "gpt-5-codex"])
        #expect(capabilities.reasoningEfforts == ["auto", "low", "medium", "high", "max"])
        #expect(request?.machineID == "machine-1")
        #expect(request?.agent == .codex)
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
                NewSessionSpawnRequest(
                    serverURLString: "https://api.unhappy.im",
                    token: "token",
                    machineID: "machine-1",
                    directory: "/tmp/new",
                    agent: .claude,
                    approvedNewDirectoryCreation: false,
                    codexResumeThreadID: nil,
                    claudeResumeSessionID: nil,
                    sessionToken: nil,
                    environmentVariables: [:],
                    model: nil,
                    reasoningEffort: nil
                )
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
            NewSessionSpawnRequest(
                serverURLString: "https://api.unhappy.im",
                token: "token",
                machineID: "machine-1",
                directory: "/repo",
                agent: .codex,
                approvedNewDirectoryCreation: true,
                codexResumeThreadID: "thread-123",
                claudeResumeSessionID: "claude-456",
                sessionToken: "session-token",
                environmentVariables: ["OPENAI_API_KEY": "test-key"],
                model: "gpt-5-codex",
                reasoningEffort: .high
            )
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
        #expect(request?.model == "gpt-5-codex")
        #expect(request?.reasoningEffort == .high)
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

    @Test
    func recentProjectsUseCaseNormalizesHomeAliases() async {
        let suiteName = "im.unhappy.newsession.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("failed to create UserDefaults test suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let useCase = NewSessionRecentProjectsUseCase(store: store, maxProjects: 8)

        _ = await useCase.recordRecentProject("/Users/skyline23/Downloads/unhappy")
        _ = await useCase.recordRecentProject("~/Downloads/unhappy")
        _ = await useCase.recordRecentProject("/Users/skyline23/Downloads/space-os/")

        #expect(await useCase.loadRecentProjects() == ["~/Downloads/space-os", "~/Downloads/unhappy"])
    }

    @Test
    func recentProjectsUseCaseCleansLegacyMixedFormatsOnLoad() async {
        let suiteName = "im.unhappy.newsession.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("failed to create UserDefaults test suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        await store.setRecentProjectPaths([
            "/Users/skyline23/Downloads/unhappy",
            "~/Downloads/unhappy",
            "/Users/skyline23/Downloads/space-os"
        ])

        let useCase = NewSessionRecentProjectsUseCase(store: store, maxProjects: 8)
        let normalized = await useCase.loadRecentProjects()

        #expect(normalized == ["~/Downloads/unhappy", "~/Downloads/space-os"])
        #expect(await store.recentProjectPaths() == ["~/Downloads/unhappy", "~/Downloads/space-os"])
    }

    @Test
    func profilesUseCaseSavesLoadsAndDeletes() async {
        let suiteName = "im.unhappy.newsession.profiles.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("failed to create UserDefaults test suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsNewSessionProfilesStore(defaults: defaults)
        let useCase = NewSessionProfilesUseCase(store: store, maxProfiles: 5)

        let profile = NewSessionProfile(
            id: "profile-1",
            name: "Main Repo",
            machineID: "machine-1",
            directoryPath: "/repo/main",
            agent: .codex,
            codexResumeThreadID: "thread-1",
            claudeResumeSessionID: nil,
            sessionToken: nil,
            environmentVariablesText: "OPENAI_API_KEY=test"
        )

        let saved = await useCase.saveProfile(profile)
        #expect(saved.count == 1)
        #expect(saved.first?.name == "Main Repo")

        let loaded = await useCase.loadProfiles()
        #expect(loaded == saved)

        let deleted = await useCase.deleteProfile(id: "profile-1")
        #expect(deleted.isEmpty)
    }

    @Test
    func profilesUseCaseReplacesExistingByID() async {
        let suiteName = "im.unhappy.newsession.profiles.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("failed to create UserDefaults test suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsNewSessionProfilesStore(defaults: defaults)
        let useCase = NewSessionProfilesUseCase(store: store, maxProfiles: 5)

        _ = await useCase.saveProfile(
            NewSessionProfile(
                id: "profile-1",
                name: "Main Repo",
                machineID: "machine-1",
                directoryPath: "/repo/main",
                agent: .codex,
                codexResumeThreadID: nil,
                claudeResumeSessionID: nil,
                sessionToken: nil,
                environmentVariablesText: ""
            )
        )
        let updated = await useCase.saveProfile(
            NewSessionProfile(
                id: "profile-1",
                name: "Main Repo Updated",
                machineID: "machine-2",
                directoryPath: "/repo/updated",
                agent: .claude,
                codexResumeThreadID: nil,
                claudeResumeSessionID: "claude-1",
                sessionToken: nil,
                environmentVariablesText: "FOO=BAR"
            )
        )

        #expect(updated.count == 1)
        #expect(updated.first?.name == "Main Repo Updated")
        #expect(updated.first?.machineID == "machine-2")
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

private struct ThreadsRequest: Equatable {
    let machineID: String
    let limit: Int
    let cwd: String?
    let cursor: String?
}

private actor CodexThreadsService: MachineCodexThreadsFetching {
    let page: APICodexThreadsPage
    var lastRequest: ThreadsRequest?

    init(page: APICodexThreadsPage) {
        self.page = page
        self.lastRequest = nil
    }

    func fetchCodexThreadsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APICodexThreadsPage {
        lastRequest = ThreadsRequest(
            machineID: machineID,
            limit: limit,
            cwd: cwd,
            cursor: cursor
        )
        return page
    }

    func fetchCodexThreads(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?
    ) async throws -> [APICodexThreadSummary] {
        page.threads
    }
}

private actor ClaudeSessionsService: MachineClaudeSessionsFetching {
    let page: APIClaudeSessionsPage
    var lastRequest: ThreadsRequest?

    init(page: APIClaudeSessionsPage) {
        self.page = page
        self.lastRequest = nil
    }

    func fetchClaudeSessionsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APIClaudeSessionsPage {
        lastRequest = ThreadsRequest(
            machineID: machineID,
            limit: limit,
            cwd: cwd,
            cursor: cursor
        )
        return page
    }

    func fetchClaudeSessions(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?
    ) async throws -> [APIClaudeSessionSummary] {
        page.sessions
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
    let model: String?
    let reasoningEffort: APISessionReasoningEffort?
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
        environmentVariables: [String : String]?,
        model: String?,
        reasoningEffort: APISessionReasoningEffort?
    ) async throws -> APISessionSpawnResult {
        lastRequest = SpawnRequest(
            machineID: machineID,
            directory: directory,
            agent: agent,
            codexResumeThreadID: codexResumeThreadID,
            claudeResumeSessionID: claudeResumeSessionID,
            approvedNewDirectoryCreation: approvedNewDirectoryCreation,
            sessionToken: sessionToken,
            environmentVariables: environmentVariables,
            model: model,
            reasoningEffort: reasoningEffort
        )
        return response
    }
}

private struct ModelsRequest: Equatable {
    let machineID: String
    let agent: APISessionSpawnAgent
}

private actor ModelsService: MachineModelsListing {
    let models: [String]
    var lastRequest: ModelsRequest?

    init(models: [String]) {
        self.models = models
        self.lastRequest = nil
    }

    func fetchAgentCapabilities(
        serverURL: URL,
        token: String,
        machineID: String,
        agent: APISessionSpawnAgent
    ) async throws -> APIMachineAgentCapabilities {
        lastRequest = ModelsRequest(machineID: machineID, agent: agent)
        return APIMachineAgentCapabilities(
            models: models,
            reasoningEfforts: ["auto", "low", "medium", "high", "max"]
        )
    }
}
