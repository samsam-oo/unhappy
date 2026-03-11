import Foundation
import Testing
import CoreKit
import SessionKit
@testable import FeatureSessions

struct SessionProjectSessionsUseCaseTests {
    @Test
    func loadProjectSessionsMapsUnifiedRowsIntoLinkedSessions() async throws {
        let project = SessionMachineProject(
            machineID: "machine-1",
            machineDisplayName: "Work Mac",
            wrappedMachineDataEncryptionKey: "wrapped-key",
            summary: APIMachineProjectSummary(
                path: "/repo/app",
                latestUpdatedAt: "2026-03-06T04:00:00.000Z",
                codexThreadCount: 1,
                claudeSessionCount: 0,
                openedExplicitly: true
            )
        )
        let service = MockProjectSessionsService(
            page: APIProjectSessionsPage(
                sessions: [
                    APIUpstreamSessionSummary(
                        id: "thread-1",
                        provider: .codex,
                        title: "Fix loading",
                        cwd: "/repo/app",
                        path: "/Users/me/.codex/sessions/thread.jsonl",
                        updatedAt: "2026-03-06T05:00:00Z",
                        createdAt: "2026-03-06T04:00:00Z",
                        archived: false,
                        model: "gpt-5-codex",
                        effort: .high,
                        preview: "Fix loading",
                        statusType: nil
                    )
                ],
                nextCursor: nil,
                hasNext: false
            )
        )
        let useCase = SessionProjectSessionsLoadUseCase(service: service)

        let rows = try await useCase.loadProjectSessions(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            project: project
        )

        #expect(rows.count == 1)
        #expect(rows[0].machineID == "machine-1")
        #expect(rows[0].machineDisplayName == "Work Mac")
        #expect(rows[0].wrappedMachineDataEncryptionKey == "wrapped-key")
        #expect(rows[0].summary.id == "thread-1")
        #expect(rows[0].summary.provider == .codex)
        #expect(await service.recordedProjectPaths == ["/repo/app"])
    }

    @Test
    func loadProjectSessionsThrowsWhenProjectFeedReturnsOnlyError() async {
        let project = SessionMachineProject(
            machineID: "machine-1",
            machineDisplayName: "Work Mac",
            wrappedMachineDataEncryptionKey: nil,
            summary: APIMachineProjectSummary(
                path: "/repo/app",
                latestUpdatedAt: "2026-03-06T04:00:00.000Z",
                codexThreadCount: 1,
                claudeSessionCount: 0,
                openedExplicitly: true
            )
        )
        let service = MockProjectSessionsService(
            page: APIProjectSessionsPage(
                sessions: [],
                nextCursor: nil,
                hasNext: false,
                error: "Machine daemon is not connected"
            )
        )
        let useCase = SessionProjectSessionsLoadUseCase(service: service)

        await #expect(throws: MachinesAPIError.rpcCallFailed("Machine daemon is not connected")) {
            _ = try await useCase.loadProjectSessions(
                serverURLString: "https://api.unhappy.im",
                token: "token",
                project: project
            )
        }
    }
}

private actor MockProjectSessionsService: MachinesFetching, MachineProjectSessionsFetching {
    let page: APIProjectSessionsPage
    private(set) var recordedProjectPaths: [String] = []

    init(page: APIProjectSessionsPage) {
        self.page = page
    }

    func fetchMachines(serverURL: URL, token: String) async throws -> [APIMachine] {
        []
    }

    func fetchProjectSessionsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        projectPath: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APIProjectSessionsPage {
        recordedProjectPaths.append(projectPath)
        return page
    }
}
