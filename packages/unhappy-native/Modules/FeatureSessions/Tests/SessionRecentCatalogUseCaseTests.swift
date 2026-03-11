import Foundation
import Testing
import CoreKit
import SessionKit
@testable import FeatureSessions

struct SessionRecentCatalogUseCaseTests {
    @Test
    func loadRecentSessionsMapsCatalogRowsIntoLinkedSessions() async throws {
        let service = MockRecentCatalogService(
            machines: [
                APIMachine(
                    id: "machine-1",
                    active: true,
                    activeAt: 1,
                    createdAt: 1,
                    updatedAt: 1,
                    metadataVersion: 1,
                    metadata: #"{"host":"Work Mac"}"#,
                    daemonStateVersion: 1,
                    daemonState: nil,
                    dataEncryptionKey: "wrapped-key"
                )
            ],
            page: APIRecentCatalogSessionsPage(
                sessions: [
                    APICatalogSessionSummary(
                        machineID: "machine-1",
                        summary: APIUpstreamSessionSummary(
                            id: "thread-1",
                            provider: .codex,
                            title: "Fix loading",
                            cwd: "/repo/app",
                            path: "/tmp/thread.jsonl",
                            updatedAt: "2026-03-11T00:00:00Z",
                            createdAt: "2026-03-10T23:00:00Z",
                            archived: false,
                            model: "gpt-5-codex",
                            effort: nil,
                            preview: "Fix loading",
                            statusType: nil
                        )
                    )
                ],
                nextCursor: nil,
                hasNext: false
            )
        )
        let useCase = SessionRecentCatalogLoadUseCase(service: service)

        let rows = try await useCase.loadRecentSessions(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(rows.count == 1)
        #expect(rows[0].machineID == "machine-1")
        #expect(rows[0].wrappedMachineDataEncryptionKey == "wrapped-key")
        #expect(rows[0].summary.id == "thread-1")
    }
}

private actor MockRecentCatalogService: MachinesFetching, MachineRecentSessionCatalogFetching {
    let machines: [APIMachine]
    let page: APIRecentCatalogSessionsPage

    init(
        machines: [APIMachine],
        page: APIRecentCatalogSessionsPage
    ) {
        self.machines = machines
        self.page = page
    }

    func fetchMachines(serverURL: URL, token: String) async throws -> [APIMachine] {
        machines
    }

    func fetchRecentSessionCatalogPage(
        serverURL: URL,
        token: String,
        limit: Int,
        cursor: String?
    ) async throws -> APIRecentCatalogSessionsPage {
        page
    }
}
