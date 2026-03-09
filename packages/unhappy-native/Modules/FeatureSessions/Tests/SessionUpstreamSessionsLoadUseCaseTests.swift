import Foundation
import Testing
@testable import FeatureSessions
import CoreKit

struct SessionUpstreamSessionsLoadUseCaseTests {
    @Test
    func loadUpstreamSessionsCombinesProvidersAndSortsNewestFirst() async throws {
        let project = SessionMachineProject(
            machineID: "machine-1",
            machineDisplayName: "Work Mac",
            summary: APIMachineProjectSummary(
                path: "/tmp/project",
                latestUpdatedAt: "2026-03-06T05:00:00.000Z",
                codexThreadCount: 0,
                claudeSessionCount: 0,
                openedExplicitly: true
            )
        )
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
            codexThreadsByMachineAndPath: [
                "machine-1|/tmp/project": [
                    APICodexThreadSummary(
                        id: "thread-1",
                        name: "Older Codex",
                        cwd: "/tmp/project",
                        updatedAt: "2026-03-06T03:00:00.000Z",
                        createdAt: "2026-03-06T02:00:00.000Z",
                        archived: false
                    )
                ]
            ],
            claudeSessionsByMachineAndPath: [
                "machine-1|/tmp/project": [
                    APIClaudeSessionSummary(
                        id: "claude-1",
                        cwd: "/tmp/project",
                        updatedAt: "2026-03-06T04:00:00.000Z",
                        createdAt: "2026-03-06T03:00:00.000Z"
                    )
                ]
            ],
            geminiSessionsByMachineAndPath: [
                "machine-1|/tmp/project": [
                    APIGeminiSessionSummary(
                        id: "gemini-1",
                        title: "Newest Gemini",
                        cwd: "/tmp/project",
                        updatedAt: "2026-03-06T05:30:00.000Z",
                        createdAt: "2026-03-06T05:15:00.000Z",
                        model: "gemini-3-flash-preview"
                    )
                ]
            ]
        )
        let useCase = SessionUpstreamSessionsLoadUseCase(service: service)

        let rows = try await useCase.loadUpstreamSessions(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            projects: [project]
        )

        #expect(rows.map(\.id) == [
            "machine-1|gemini|gemini-1",
            "machine-1|claude|claude-1",
            "machine-1|codex|thread-1"
        ])
        #expect(rows.first?.machineDisplayName == "Work Mac")
    }

    @Test
    func loadUpstreamSessionsIgnoresInactiveMachines() async throws {
        let project = SessionMachineProject(
            machineID: "machine-active",
            machineDisplayName: "Active Mac",
            summary: APIMachineProjectSummary(
                path: "/tmp/active",
                latestUpdatedAt: "2026-03-06T05:00:00.000Z",
                codexThreadCount: 0,
                claudeSessionCount: 0,
                openedExplicitly: true
            )
        )
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
            codexThreadsByMachineAndPath: [
                "machine-active|/tmp/active": [
                    APICodexThreadSummary(
                        id: "thread-active",
                        name: "Active Thread",
                        cwd: "/tmp/active",
                        updatedAt: "2026-03-06T05:00:00.000Z",
                        createdAt: "2026-03-06T04:00:00.000Z",
                        archived: false
                    )
                ],
                "machine-inactive|/tmp/inactive": [
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
            claudeSessionsByMachineAndPath: [:],
            geminiSessionsByMachineAndPath: [:]
        )
        let useCase = SessionUpstreamSessionsLoadUseCase(service: service)

        let rows = try await useCase.loadUpstreamSessions(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            projects: [project]
        )

        #expect(rows.count == 1)
        #expect(rows.first?.machineID == "machine-active")
        #expect(rows.first?.summary.id == "thread-active")
    }

    @Test
    func loadUpstreamSessionsDeduplicatesProjectPathsPerMachineBeforeFetching() async throws {
        let duplicateProjects = [
            SessionMachineProject(
                machineID: "machine-1",
                machineDisplayName: "Work Mac",
                summary: APIMachineProjectSummary(
                    path: "/tmp/project",
                    latestUpdatedAt: "2026-03-06T05:00:00.000Z",
                    codexThreadCount: 0,
                    claudeSessionCount: 0,
                    openedExplicitly: true
                )
            ),
            SessionMachineProject(
                machineID: "machine-1",
                machineDisplayName: "Work Mac",
                summary: APIMachineProjectSummary(
                    path: "/tmp/project",
                    latestUpdatedAt: "2026-03-06T05:00:00.000Z",
                    codexThreadCount: 0,
                    claudeSessionCount: 0,
                    openedExplicitly: true
                )
            )
        ]
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
            codexThreadsByMachineAndPath: [:],
            claudeSessionsByMachineAndPath: [:],
            geminiSessionsByMachineAndPath: [:]
        )
        let useCase = SessionUpstreamSessionsLoadUseCase(service: service)

        _ = try await useCase.loadUpstreamSessions(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            projects: duplicateProjects
        )

        let codexFetchCount = await service.codexFetchCount
        let claudeFetchCount = await service.claudeFetchCount
        let geminiFetchCount = await service.geminiFetchCount
        #expect(codexFetchCount == 1)
        #expect(claudeFetchCount == 1)
        #expect(geminiFetchCount == 1)
    }
}

private actor MockUpstreamMachinesService: MachinesFetching, MachineCodexThreadsFetching, MachineClaudeSessionsFetching, MachineGeminiSessionsFetching {
    let machines: [APIMachine]
    let codexThreadsByMachineAndPath: [String: [APICodexThreadSummary]]
    let claudeSessionsByMachineAndPath: [String: [APIClaudeSessionSummary]]
    let geminiSessionsByMachineAndPath: [String: [APIGeminiSessionSummary]]
    private(set) var codexFetchCount = 0
    private(set) var claudeFetchCount = 0
    private(set) var geminiFetchCount = 0

    init(
        machines: [APIMachine],
        codexThreadsByMachineAndPath: [String: [APICodexThreadSummary]],
        claudeSessionsByMachineAndPath: [String: [APIClaudeSessionSummary]],
        geminiSessionsByMachineAndPath: [String: [APIGeminiSessionSummary]]
    ) {
        self.machines = machines
        self.codexThreadsByMachineAndPath = codexThreadsByMachineAndPath
        self.claudeSessionsByMachineAndPath = claudeSessionsByMachineAndPath
        self.geminiSessionsByMachineAndPath = geminiSessionsByMachineAndPath
    }

    func fetchMachines(serverURL: URL, token: String) async throws -> [APIMachine] {
        machines
    }

    func fetchCodexThreadsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APICodexThreadsPage {
        let key = "\(machineID)|\(cwd ?? "")"
        return APICodexThreadsPage(
            threads: codexThreadsByMachineAndPath[key] ?? [],
            nextCursor: nil,
            hasNext: false
        )
    }

    func fetchCodexThreads(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?
    ) async throws -> [APICodexThreadSummary] {
        codexFetchCount += 1
        codexThreadsByMachineAndPath["\(machineID)|\(cwd ?? "")"] ?? []
    }

    func fetchClaudeSessionsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APIClaudeSessionsPage {
        let key = "\(machineID)|\(cwd ?? "")"
        return APIClaudeSessionsPage(
            sessions: claudeSessionsByMachineAndPath[key] ?? [],
            nextCursor: nil,
            hasNext: false
        )
    }

    func fetchClaudeSessions(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?
    ) async throws -> [APIClaudeSessionSummary] {
        claudeFetchCount += 1
        claudeSessionsByMachineAndPath["\(machineID)|\(cwd ?? "")"] ?? []
    }

    func fetchGeminiSessionsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APIGeminiSessionsPage {
        let key = "\(machineID)|\(cwd ?? "")"
        return APIGeminiSessionsPage(
            sessions: geminiSessionsByMachineAndPath[key] ?? [],
            nextCursor: nil,
            hasNext: false
        )
    }

    func fetchGeminiSessions(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?
    ) async throws -> [APIGeminiSessionSummary] {
        geminiFetchCount += 1
        geminiSessionsByMachineAndPath["\(machineID)|\(cwd ?? "")"] ?? []
    }
}
