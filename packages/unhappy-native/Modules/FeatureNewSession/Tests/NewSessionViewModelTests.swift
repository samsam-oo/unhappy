import Foundation
import Testing
import CoreKit
@testable import FeatureNewSession

@MainActor
struct NewSessionViewModelTests {
    @Test
    func loadCodexThreadsLoadsFirstPageMetadata() async throws {
        let machine = makeMachine(id: "machine-1")
        let firstPage = APICodexThreadsPage(
            threads: [
                APICodexThreadSummary(
                    id: "thread-1",
                    name: "First",
                    cwd: "/repo",
                    updatedAt: "2026-02-26T11:00:00.000Z",
                    createdAt: "2026-02-26T10:00:00.000Z",
                    archived: false
                )
            ],
            nextCursor: "cursor-20",
            hasNext: true
        )
        let model = NewSessionViewModel(
            machinesLoader: ViewModelMachinesLoader(machines: [machine]),
            directoryLister: ViewModelDirectoryLister(),
            spawner: ViewModelSpawner(),
            recentProjectsManager: NewSessionNoopRecentProjectsManager(),
            profilesManager: NewSessionNoopProfilesManager(),
            codexThreadsLoader: SequenceCodexThreadsLoader(pages: [firstPage]),
            claudeSessionsLoader: SequenceClaudeSessionsLoader(pages: [])
        )

        await model.loadMachines(serverURLString: "https://api.unhappy.im", token: "token")
        await model.loadCodexThreads(serverURLString: "https://api.unhappy.im", token: "token")

        #expect(model.codexThreads.map(\.id) == ["thread-1"])
        #expect(model.codexThreadsHasNext == true)
        #expect(model.codexThreadsErrorMessage == nil)
        #expect(model.isLoadingCodexThreads == false)
    }

    @Test
    func loadMoreCodexThreadsAppendsUniqueRows() async throws {
        let machine = makeMachine(id: "machine-1")
        let firstPage = APICodexThreadsPage(
            threads: [
                APICodexThreadSummary(
                    id: "thread-1",
                    name: "First",
                    cwd: "/repo",
                    updatedAt: "2026-02-26T11:00:00.000Z",
                    createdAt: "2026-02-26T10:00:00.000Z",
                    archived: false
                )
            ],
            nextCursor: "cursor-20",
            hasNext: true
        )
        let secondPage = APICodexThreadsPage(
            threads: [
                APICodexThreadSummary(
                    id: "thread-1",
                    name: "First",
                    cwd: "/repo",
                    updatedAt: "2026-02-26T11:00:00.000Z",
                    createdAt: "2026-02-26T10:00:00.000Z",
                    archived: false
                ),
                APICodexThreadSummary(
                    id: "thread-2",
                    name: "Second",
                    cwd: "/repo",
                    updatedAt: "2026-02-26T11:10:00.000Z",
                    createdAt: "2026-02-26T10:10:00.000Z",
                    archived: false
                )
            ],
            nextCursor: nil,
            hasNext: false
        )
        let loader = SequenceCodexThreadsLoader(pages: [firstPage, secondPage])
        let model = NewSessionViewModel(
            machinesLoader: ViewModelMachinesLoader(machines: [machine]),
            directoryLister: ViewModelDirectoryLister(),
            spawner: ViewModelSpawner(),
            recentProjectsManager: NewSessionNoopRecentProjectsManager(),
            profilesManager: NewSessionNoopProfilesManager(),
            codexThreadsLoader: loader,
            claudeSessionsLoader: SequenceClaudeSessionsLoader(pages: [])
        )

        await model.loadMachines(serverURLString: "https://api.unhappy.im", token: "token")
        await model.loadCodexThreads(serverURLString: "https://api.unhappy.im", token: "token")
        await model.loadMoreCodexThreads(serverURLString: "https://api.unhappy.im", token: "token")

        #expect(model.codexThreads.map(\.id) == ["thread-1", "thread-2"])
        #expect(model.codexThreadsHasNext == false)
        #expect(model.codexThreadsErrorMessage == nil)
        #expect(model.isLoadingMoreCodexThreads == false)

        let cursors = await loader.recordedCursors
        #expect(cursors == [nil, "cursor-20"])
    }

    @Test
    func loadMoreClaudeSessionsUsesCursorAndUpdatesState() async throws {
        let machine = makeMachine(id: "machine-1")
        let firstPage = APIClaudeSessionsPage(
            sessions: [
                APIClaudeSessionSummary(
                    id: "claude-1",
                    cwd: "/repo",
                    updatedAt: "2026-02-26T11:00:00.000Z",
                    createdAt: "2026-02-26T10:00:00.000Z"
                )
            ],
            nextCursor: "cursor-12",
            hasNext: true
        )
        let secondPage = APIClaudeSessionsPage(
            sessions: [
                APIClaudeSessionSummary(
                    id: "claude-2",
                    cwd: "/repo",
                    updatedAt: "2026-02-26T11:10:00.000Z",
                    createdAt: "2026-02-26T10:10:00.000Z"
                )
            ],
            nextCursor: nil,
            hasNext: false
        )
        let loader = SequenceClaudeSessionsLoader(pages: [firstPage, secondPage])
        let model = NewSessionViewModel(
            machinesLoader: ViewModelMachinesLoader(machines: [machine]),
            directoryLister: ViewModelDirectoryLister(),
            spawner: ViewModelSpawner(),
            recentProjectsManager: NewSessionNoopRecentProjectsManager(),
            profilesManager: NewSessionNoopProfilesManager(),
            codexThreadsLoader: SequenceCodexThreadsLoader(pages: []),
            claudeSessionsLoader: loader
        )

        await model.loadMachines(serverURLString: "https://api.unhappy.im", token: "token")
        await model.loadClaudeSessions(serverURLString: "https://api.unhappy.im", token: "token")
        await model.loadMoreClaudeSessions(serverURLString: "https://api.unhappy.im", token: "token")

        #expect(model.claudeSessions.map(\.id) == ["claude-1", "claude-2"])
        #expect(model.claudeSessionsHasNext == false)
        #expect(model.claudeSessionsErrorMessage == nil)
        #expect(model.isLoadingMoreClaudeSessions == false)

        let cursors = await loader.recordedCursors
        #expect(cursors == [nil, "cursor-12"])
    }

    @Test
    func loadMachinesStopsMachineSpinnerBeforeDirectoryLoadCompletes() async throws {
        let machine = makeMachine(id: "machine-1")
        let lister = SuspendingDirectoryLister()
        let model = NewSessionViewModel(
            machinesLoader: ViewModelMachinesLoader(machines: [machine]),
            directoryLister: lister,
            spawner: ViewModelSpawner(),
            recentProjectsManager: NewSessionNoopRecentProjectsManager(),
            profilesManager: NewSessionNoopProfilesManager(),
            codexThreadsLoader: SequenceCodexThreadsLoader(pages: []),
            claudeSessionsLoader: SequenceClaudeSessionsLoader(pages: [])
        )

        let task = Task {
            await model.loadMachines(serverURLString: "https://api.unhappy.im", token: "token")
        }

        await lister.waitUntilStarted()
        await Task.yield()

        #expect(model.isLoadingMachines == false)
        #expect(model.isLoadingDirectory == true)

        await lister.resume()
        await task.value
    }

    @Test
    func loadDirectoryRecoversFromMissingMachineByRefreshingMachines() async throws {
        let machine1 = makeMachine(id: "machine-1")
        let machine2 = makeMachine(id: "machine-2")
        let machinesLoader = SequenceMachinesLoader(pages: [[machine1], [machine2]])
        let lister = SequenceDirectoryLister(results: [
            .success([]),
            .failure(MachinesAPIError.invalidHTTPStatus(404)),
            .success([
                APIMachineDirectoryEntry(name: "Sources", type: "directory", size: nil, modified: nil)
            ]),
        ])

        let model = NewSessionViewModel(
            machinesLoader: machinesLoader,
            directoryLister: lister,
            spawner: ViewModelSpawner(),
            recentProjectsManager: NewSessionNoopRecentProjectsManager(),
            profilesManager: NewSessionNoopProfilesManager(),
            codexThreadsLoader: SequenceCodexThreadsLoader(pages: []),
            claudeSessionsLoader: SequenceClaudeSessionsLoader(pages: [])
        )

        await model.loadMachines(serverURLString: "https://api.unhappy.im", token: "token")
        #expect(model.selectedMachineID == "machine-1")

        await model.loadDirectory(serverURLString: "https://api.unhappy.im", token: "token")

        #expect(model.selectedMachineID == "machine-2")
        #expect(model.directoryEntries.map(\.name) == ["Sources"])
        #expect(model.errorMessage == nil)
    }

    @Test
    func loadDirectory404ShowsHelpfulMessageWhenRecoveryFails() async throws {
        let machine1 = makeMachine(id: "machine-1")
        let machinesLoader = SequenceMachinesLoader(
            pages: [[machine1]],
            fallbackError: NewSessionError.failed(message: "refresh failed")
        )
        let lister = SequenceDirectoryLister(results: [
            .success([]),
            .failure(MachinesAPIError.invalidHTTPStatus(404)),
        ])

        let model = NewSessionViewModel(
            machinesLoader: machinesLoader,
            directoryLister: lister,
            spawner: ViewModelSpawner(),
            recentProjectsManager: NewSessionNoopRecentProjectsManager(),
            profilesManager: NewSessionNoopProfilesManager(),
            codexThreadsLoader: SequenceCodexThreadsLoader(pages: []),
            claudeSessionsLoader: SequenceClaudeSessionsLoader(pages: [])
        )

        await model.loadMachines(serverURLString: "https://api.unhappy.im", token: "token")
        await model.loadDirectory(serverURLString: "https://api.unhappy.im", token: "token")

        let message = model.errorMessage ?? ""
        #expect(message.contains("Folder list failed (404)"))
        #expect(model.directoryEntries.isEmpty)
    }

    @Test
    func loadDirectoryRecoversWhen404ComesAsNewSessionErrorMessage() async throws {
        let machine1 = makeMachine(id: "machine-1")
        let machine2 = makeMachine(id: "machine-2")
        let machinesLoader = SequenceMachinesLoader(pages: [[machine1], [machine2]])
        let lister = SequenceDirectoryLister(results: [
            .success([]),
            .failure(NewSessionError.failed(message: "Request failed with status 404")),
            .success([
                APIMachineDirectoryEntry(name: "App", type: "directory", size: nil, modified: nil)
            ]),
        ])

        let model = NewSessionViewModel(
            machinesLoader: machinesLoader,
            directoryLister: lister,
            spawner: ViewModelSpawner(),
            recentProjectsManager: NewSessionNoopRecentProjectsManager(),
            profilesManager: NewSessionNoopProfilesManager(),
            codexThreadsLoader: SequenceCodexThreadsLoader(pages: []),
            claudeSessionsLoader: SequenceClaudeSessionsLoader(pages: [])
        )

        await model.loadMachines(serverURLString: "https://api.unhappy.im", token: "token")
        await model.loadDirectory(serverURLString: "https://api.unhappy.im", token: "token")

        #expect(model.selectedMachineID == "machine-2")
        #expect(model.directoryEntries.map(\.name) == ["App"])
        #expect(model.errorMessage == nil)
    }

    @Test
    func loadDirectoryShowsBackendUpdateMessageWhenEndpointMissing() async throws {
        let machine1 = makeMachine(id: "machine-1")
        let lister = SequenceDirectoryLister(results: [
            .success([]),
            .failure(MachinesAPIError.endpointUnavailable("/v1/machines/:id/commands/list-directory")),
        ])

        let model = NewSessionViewModel(
            machinesLoader: SequenceMachinesLoader(pages: [[machine1]]),
            directoryLister: lister,
            spawner: ViewModelSpawner(),
            recentProjectsManager: NewSessionNoopRecentProjectsManager(),
            profilesManager: NewSessionNoopProfilesManager(),
            codexThreadsLoader: SequenceCodexThreadsLoader(pages: []),
            claudeSessionsLoader: SequenceClaudeSessionsLoader(pages: [])
        )

        await model.loadMachines(serverURLString: "https://api.unhappy.im", token: "token")
        await model.loadDirectory(serverURLString: "https://api.unhappy.im", token: "token")

        let message = model.errorMessage ?? ""
        #expect(message.contains("Folder browse API is not deployed"))
        #expect(model.directoryEntries.isEmpty)
    }

    @Test
    func selectCodexThreadSetsResumeStateAndDirectoryFromThread() async throws {
        let model = NewSessionViewModel(
            machinesLoader: ViewModelMachinesLoader(machines: [makeMachine(id: "machine-1")]),
            directoryLister: ViewModelDirectoryLister(),
            spawner: ViewModelSpawner(),
            recentProjectsManager: NewSessionNoopRecentProjectsManager(),
            profilesManager: NewSessionNoopProfilesManager(),
            codexThreadsLoader: SequenceCodexThreadsLoader(pages: []),
            claudeSessionsLoader: SequenceClaudeSessionsLoader(pages: [])
        )

        await model.loadMachines(serverURLString: "https://api.unhappy.im", token: "token")
        model.selectCodexThread(
            APICodexThreadSummary(
                id: "thread-123",
                name: "Resume Target",
                cwd: "/Users/skyline23/Downloads/unhappy",
                updatedAt: nil,
                createdAt: nil,
                archived: false,
                model: "gpt-5-codex",
                effort: .high
            )
        )

        #expect(model.selectedAgent == .codex)
        #expect(model.codexResumeThreadID == "thread-123")
        #expect(model.claudeResumeSessionID.isEmpty)
        #expect(model.directoryPath == "/Users/skyline23/Downloads/unhappy")
        #expect(model.selectedModel == "gpt-5-codex")
        #expect(model.selectedReasoningEffort == .high)
    }

    @Test
    func selectClaudeSessionSetsResumeStateAndDirectoryFromSession() async throws {
        let model = NewSessionViewModel(
            machinesLoader: ViewModelMachinesLoader(machines: [makeMachine(id: "machine-1")]),
            directoryLister: ViewModelDirectoryLister(),
            spawner: ViewModelSpawner(),
            recentProjectsManager: NewSessionNoopRecentProjectsManager(),
            profilesManager: NewSessionNoopProfilesManager(),
            codexThreadsLoader: SequenceCodexThreadsLoader(pages: []),
            claudeSessionsLoader: SequenceClaudeSessionsLoader(pages: [])
        )

        await model.loadMachines(serverURLString: "https://api.unhappy.im", token: "token")
        model.selectClaudeSession(
            APIClaudeSessionSummary(
                id: "claude-456",
                cwd: "~/Downloads/unhappy",
                updatedAt: nil,
                createdAt: nil
            )
        )

        #expect(model.selectedAgent == .claude)
        #expect(model.claudeResumeSessionID == "claude-456")
        #expect(model.codexResumeThreadID.isEmpty)
        #expect(model.directoryPath == "~/Downloads/unhappy")
    }

    @Test
    func applyProjectContextSetsDirectoryAndClearsResumeSelections() async throws {
        let model = NewSessionViewModel(
            machinesLoader: ViewModelMachinesLoader(machines: [makeMachine(id: "machine-1")]),
            directoryLister: ViewModelDirectoryLister(),
            spawner: ViewModelSpawner(),
            recentProjectsManager: NewSessionNoopRecentProjectsManager(),
            profilesManager: NewSessionNoopProfilesManager(),
            codexThreadsLoader: SequenceCodexThreadsLoader(pages: []),
            claudeSessionsLoader: SequenceClaudeSessionsLoader(pages: [])
        )

        await model.loadMachines(serverURLString: "https://api.unhappy.im", token: "token")
        model.selectCodexThread(
            APICodexThreadSummary(
                id: "thread-123",
                name: "Resume Target",
                cwd: "/repo/old",
                updatedAt: nil,
                createdAt: nil,
                archived: false
            )
        )

        await model.applyProjectContext(
            machineID: "machine-1",
            directoryPath: "/repo/app",
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(model.selectedMachineID == "machine-1")
        #expect(model.directoryPath == "/repo/app")
        #expect(model.codexResumeThreadID.isEmpty)
        #expect(model.claudeResumeSessionID.isEmpty)
    }
}

private func makeMachine(id: String) -> APIMachine {
    APIMachine(
        id: id,
        active: true,
        activeAt: 10,
        createdAt: 1,
        updatedAt: 10,
        metadataVersion: 1,
        metadata: "enc",
        daemonStateVersion: 0,
        daemonState: nil,
        dataEncryptionKey: nil
    )
}

private struct ViewModelMachinesLoader: NewSessionMachinesLoadingAction {
    let machines: [APIMachine]

    func loadMachines(serverURLString: String, token: String) async throws -> [APIMachine] {
        machines
    }
}

private actor SequenceMachinesLoader: NewSessionMachinesLoadingAction {
    private var pages: [[APIMachine]]
    private let fallbackError: Error?

    init(pages: [[APIMachine]], fallbackError: Error? = nil) {
        self.pages = pages
        self.fallbackError = fallbackError
    }

    func loadMachines(serverURLString: String, token: String) async throws -> [APIMachine] {
        if !pages.isEmpty {
            return pages.removeFirst()
        }
        if let fallbackError {
            throw fallbackError
        }
        return []
    }
}

private struct ViewModelDirectoryLister: NewSessionDirectoryListingAction {
    func listDirectory(
        serverURLString: String,
        token: String,
        machineID: String,
        path: String
    ) async throws -> [APIMachineDirectoryEntry] {
        []
    }
}

private actor SequenceDirectoryLister: NewSessionDirectoryListingAction {
    private var results: [Result<[APIMachineDirectoryEntry], Error>]

    init(results: [Result<[APIMachineDirectoryEntry], Error>]) {
        self.results = results
    }

    func listDirectory(
        serverURLString: String,
        token: String,
        machineID: String,
        path: String
    ) async throws -> [APIMachineDirectoryEntry] {
        guard !results.isEmpty else { return [] }
        let next = results.removeFirst()
        switch next {
        case .success(let rows):
            return rows
        case .failure(let error):
            throw error
        }
    }
}

private actor SuspendingDirectoryLister: NewSessionDirectoryListingAction {
    private var hasStarted = false
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func listDirectory(
        serverURLString: String,
        token: String,
        machineID: String,
        path: String
    ) async throws -> [APIMachineDirectoryEntry] {
        hasStarted = true
        startedContinuation?.resume()
        startedContinuation = nil

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            resumeContinuation = continuation
        }
        return []
    }

    func waitUntilStarted() async {
        if hasStarted {
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            startedContinuation = continuation
        }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}

private struct ViewModelSpawner: NewSessionSpawningAction {
    func spawnSession(_ request: NewSessionSpawnRequest) async throws -> APISessionSpawnResult {
        APISessionSpawnResult(
            success: true,
            sessionID: "session-1",
            requiresUserApproval: nil,
            actionRequired: nil,
            directory: nil,
            error: nil
        )
    }
}

private actor SequenceCodexThreadsLoader: NewSessionCodexThreadsLoadingAction {
    private var pages: [APICodexThreadsPage]
    private(set) var recordedCursors: [String?] = []

    init(pages: [APICodexThreadsPage]) {
        self.pages = pages
    }

    func loadCodexThreads(
        serverURLString: String,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APICodexThreadsPage {
        recordedCursors.append(cursor)
        if pages.isEmpty {
            return APICodexThreadsPage(threads: [], nextCursor: nil, hasNext: false)
        }
        return pages.removeFirst()
    }
}

private actor SequenceClaudeSessionsLoader: NewSessionClaudeSessionsLoadingAction {
    private var pages: [APIClaudeSessionsPage]
    private(set) var recordedCursors: [String?] = []

    init(pages: [APIClaudeSessionsPage]) {
        self.pages = pages
    }

    func loadClaudeSessions(
        serverURLString: String,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APIClaudeSessionsPage {
        recordedCursors.append(cursor)
        if pages.isEmpty {
            return APIClaudeSessionsPage(sessions: [], nextCursor: nil, hasNext: false)
        }
        return pages.removeFirst()
    }
}
