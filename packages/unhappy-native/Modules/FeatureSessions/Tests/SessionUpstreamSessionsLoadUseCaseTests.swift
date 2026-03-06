import Foundation
import Testing
@testable import FeatureSessions
import CoreKit

struct SessionUpstreamSessionsLoadUseCaseTests {
    @Test
    func loadUpstreamSessionsCombinesProvidersAndSortsNewestFirst() async throws {
        let service = MockUpstreamMachinesService(
            machines: [
                APIMachine(
                    id: "machine-1",
                    active: true,
                    activeAt: 10,
                    createdAt: 1,
                    updatedAt: 10,
                    metadataVersion: 1,
                    metadata: #"{"displayName":"Work Mac"}"#,
                    daemonStateVersion: 1,
                    daemonState: nil,
                    dataEncryptionKey: nil
                )
            ],
            codexThreadsByMachineID: [
                "machine-1": [
                    APICodexThreadSummary(
                        id: "thread-1",
                        name: "Older Codex",
                        cwd: "/tmp/codex",
                        updatedAt: "2026-03-06T03:00:00.000Z",
                        createdAt: "2026-03-06T02:00:00.000Z",
                        archived: false
                    )
                ]
            ],
            claudeSessionsByMachineID: [
                "machine-1": [
                    APIClaudeSessionSummary(
                        id: "claude-1",
                        cwd: "/tmp/claude",
                        updatedAt: "2026-03-06T04:00:00.000Z",
                        createdAt: "2026-03-06T03:00:00.000Z"
                    )
                ]
            ]
        )
        let useCase = SessionUpstreamSessionsLoadUseCase(service: service)

        let rows = try await useCase.loadUpstreamSessions(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(rows.map(\.id) == [
            "machine-1|claude|claude-1",
            "machine-1|codex|thread-1"
        ])
        #expect(rows.first?.machineDisplayName == "Work Mac")
    }

    @Test
    func loadUpstreamSessionsIgnoresInactiveMachines() async throws {
        let service = MockUpstreamMachinesService(
            machines: [
                APIMachine(
                    id: "machine-active",
                    active: true,
                    activeAt: 20,
                    createdAt: 1,
                    updatedAt: 20,
                    metadataVersion: 1,
                    metadata: #"{"displayName":"Active Mac"}"#,
                    daemonStateVersion: 1,
                    daemonState: nil,
                    dataEncryptionKey: nil
                ),
                APIMachine(
                    id: "machine-inactive",
                    active: false,
                    activeAt: 0,
                    createdAt: 1,
                    updatedAt: 1,
                    metadataVersion: 1,
                    metadata: #"{"displayName":"Offline Mac"}"#,
                    daemonStateVersion: 1,
                    daemonState: nil,
                    dataEncryptionKey: nil
                )
            ],
            codexThreadsByMachineID: [
                "machine-active": [
                    APICodexThreadSummary(
                        id: "thread-active",
                        name: "Active Thread",
                        cwd: "/tmp/active",
                        updatedAt: "2026-03-06T05:00:00.000Z",
                        createdAt: "2026-03-06T04:00:00.000Z",
                        archived: false
                    )
                ],
                "machine-inactive": [
                    APICodexThreadSummary(
                        id: "thread-inactive",
                        name: "Inactive Thread",
                        cwd: "/tmp/inactive",
                        updatedAt: "2026-03-06T06:00:00.000Z",
                        createdAt: "2026-03-06T05:00:00.000Z",
                        archived: false
                    )
                ]
            ],
            claudeSessionsByMachineID: [:]
        )
        let useCase = SessionUpstreamSessionsLoadUseCase(service: service)

        let rows = try await useCase.loadUpstreamSessions(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(rows.count == 1)
        #expect(rows.first?.machineID == "machine-active")
        #expect(rows.first?.summary.id == "thread-active")
    }
}

private actor MockUpstreamMachinesService: MachinesFetching, MachineCodexThreadsFetching, MachineClaudeSessionsFetching {
    let machines: [APIMachine]
    let codexThreadsByMachineID: [String: [APICodexThreadSummary]]
    let claudeSessionsByMachineID: [String: [APIClaudeSessionSummary]]

    init(
        machines: [APIMachine],
        codexThreadsByMachineID: [String: [APICodexThreadSummary]],
        claudeSessionsByMachineID: [String: [APIClaudeSessionSummary]]
    ) {
        self.machines = machines
        self.codexThreadsByMachineID = codexThreadsByMachineID
        self.claudeSessionsByMachineID = claudeSessionsByMachineID
    }

    func fetchMachines(serverURL: URL, token: String) async throws -> [APIMachine] {
        machines
    }

    func fetchCodexThreadsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APICodexThreadsPage {
        APICodexThreadsPage(
            threads: codexThreadsByMachineID[machineID] ?? [],
            nextCursor: nil,
            hasNext: false
        )
    }

    func fetchCodexThreads(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?
    ) async throws -> [APICodexThreadSummary] {
        codexThreadsByMachineID[machineID] ?? []
    }

    func fetchClaudeSessionsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APIClaudeSessionsPage {
        APIClaudeSessionsPage(
            sessions: claudeSessionsByMachineID[machineID] ?? [],
            nextCursor: nil,
            hasNext: false
        )
    }

    func fetchClaudeSessions(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?
    ) async throws -> [APIClaudeSessionSummary] {
        claudeSessionsByMachineID[machineID] ?? []
    }
}
