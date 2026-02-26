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

private struct ViewModelSpawner: NewSessionSpawningAction {
    func spawnSession(
        serverURLString: String,
        token: String,
        machineID: String,
        directory: String,
        agent: APISessionSpawnAgent,
        approvedNewDirectoryCreation: Bool,
        codexResumeThreadID: String?,
        claudeResumeSessionID: String?,
        sessionToken: String?,
        environmentVariables: [String : String]
    ) async throws -> APISessionSpawnResult {
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
