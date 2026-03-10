import Foundation
import Testing
@testable import CoreKit

struct MachinesServiceCachingTests {
    @Test
    func fetchMachinesReusesRecentCachedResponse() async throws {
        let httpClient = CountingMachineHTTPClient(
            responseData: Data(
                """
                [
                  {
                    "id": "machine-1",
                    "active": true,
                    "activeAt": 1,
                    "createdAt": 1,
                    "updatedAt": 1,
                    "metadataVersion": 1,
                    "metadata": "{}",
                    "daemonStateVersion": 1,
                    "daemonState": "{}",
                    "dataEncryptionKey": null
                  }
                ]
                """.utf8
            )
        )
        let service = URLSessionMachinesService(
            httpClient: httpClient,
            rpcDirectoryService: NoopMachineRPCDirectoryService()
        )

        _ = try await service.fetchMachines(
            serverURL: URL(string: "https://api.unhappy.im")!,
            token: "token"
        )
        _ = try await service.fetchMachines(
            serverURL: URL(string: "https://api.unhappy.im")!,
            token: "token"
        )

        let requestCount = await httpClient.requestCount
        #expect(requestCount == 1)
    }

    @Test
    func fetchProjectsReusesRecentCachedResponse() async throws {
        let rpcDirectoryService = CountingProjectRPCDirectoryService(
            projects: [
                APIMachineProjectSummary(
                    path: "/repo/app",
                    latestUpdatedAt: "2026-03-09T12:00:00.000Z",
                    codexThreadCount: 1,
                    claudeSessionCount: 0,
                    openedExplicitly: true
                )
            ]
        )
        let service = URLSessionMachinesService(
            httpClient: CountingMachineHTTPClient(responseData: Data("[]".utf8)),
            rpcDirectoryService: rpcDirectoryService
        )

        _ = try await service.fetchProjects(
            serverURL: URL(string: "https://api.unhappy.im")!,
            token: "token",
            machineID: "machine-1",
            explicitOnly: true,
            wrappedMachineDataEncryptionKey: nil
        )
        _ = try await service.fetchProjects(
            serverURL: URL(string: "https://api.unhappy.im")!,
            token: "token",
            machineID: "machine-1",
            explicitOnly: true,
            wrappedMachineDataEncryptionKey: nil
        )

        let requestCount = await rpcDirectoryService.fetchProjectsCount
        #expect(requestCount == 1)
    }

    @Test
    func fetchMachinesPrewarmsActiveMachineDataPlane() async throws {
        let httpClient = CountingMachineHTTPClient(
            responseData: Data(
                """
                [
                  {
                    "id": "machine-1",
                    "active": true,
                    "activeAt": 1,
                    "createdAt": 1,
                    "updatedAt": 1,
                    "metadataVersion": 1,
                    "metadata": "{}",
                    "daemonStateVersion": 1,
                    "daemonState": "{}",
                    "dataEncryptionKey": "wrapped-key"
                  },
                  {
                    "id": "machine-2",
                    "active": false,
                    "activeAt": 1,
                    "createdAt": 1,
                    "updatedAt": 1,
                    "metadataVersion": 1,
                    "metadata": "{}",
                    "daemonStateVersion": 1,
                    "daemonState": "{}",
                    "dataEncryptionKey": "wrapped-key"
                  }
                ]
                """.utf8
            )
        )
        let rpcDirectoryService = PrewarmingMachineRPCDirectoryService()
        let service = URLSessionMachinesService(
            httpClient: httpClient,
            rpcDirectoryService: rpcDirectoryService
        )

        _ = try await service.fetchMachines(
            serverURL: URL(string: "https://api.unhappy.im")!,
            token: "token"
        )
        try? await Task.sleep(for: .milliseconds(50))

        let prewarmedMachineIDs = await rpcDirectoryService.prewarmedMachineIDs
        #expect(prewarmedMachineIDs == ["machine-1"])
    }

    @Test
    func fetchMachinesPrewarmsActiveMachineDataPlaneOnCacheHit() async throws {
        let httpClient = CountingMachineHTTPClient(
            responseData: Data(
                """
                [
                  {
                    "id": "machine-1",
                    "active": true,
                    "activeAt": 1,
                    "createdAt": 1,
                    "updatedAt": 1,
                    "metadataVersion": 1,
                    "metadata": "{}",
                    "daemonStateVersion": 1,
                    "daemonState": "{}",
                    "dataEncryptionKey": "wrapped-key"
                  }
                ]
                """.utf8
            )
        )
        let rpcDirectoryService = PrewarmingMachineRPCDirectoryService()
        let service = URLSessionMachinesService(
            httpClient: httpClient,
            rpcDirectoryService: rpcDirectoryService
        )

        _ = try await service.fetchMachines(
            serverURL: URL(string: "https://api.unhappy.im")!,
            token: "token"
        )
        _ = try await service.fetchMachines(
            serverURL: URL(string: "https://api.unhappy.im")!,
            token: "token"
        )
        try? await Task.sleep(for: .milliseconds(50))

        let prewarmedMachineIDs = await rpcDirectoryService.prewarmedMachineIDs
        #expect(prewarmedMachineIDs == ["machine-1", "machine-1"])
    }

    @Test
    func fetchAgentCapabilitiesPrefersRPCWhenLegacyEndpointSaysNotConnected() async throws {
        let httpClient = CountingMachineHTTPClient(
            responseData: Data(#"{"success":false,"error":"Machine daemon is not connected"}"#.utf8),
            statusCode: 409
        )
        let rpcDirectoryService = NoopMachineRPCDirectoryService(
            invokeCommandResult: .success(
                Data(
                    """
                    {
                      "models": ["gpt-5-codex"],
                      "reasoningEfforts": ["medium"],
                      "details": [
                        { "id": "gpt-5-codex", "label": "GPT-5 Codex" }
                      ]
                    }
                    """.utf8
                )
            )
        )
        let service = URLSessionMachinesService(
            httpClient: httpClient,
            rpcDirectoryService: rpcDirectoryService
        )

        let capabilities = try await service.fetchAgentCapabilities(
            serverURL: URL(string: "https://api.unhappy.im")!,
            token: "token",
            machineID: "machine-1",
            agent: .codex
        )

        #expect(capabilities.models == ["gpt-5-codex"])
        #expect(capabilities.reasoningEfforts == ["medium"])
        #expect(await httpClient.requestCount == 0)
        #expect(await rpcDirectoryService.invokedCommands == ["list-models"])
    }

    @Test
    func fetchAgentCapabilitiesFallsBackToLegacyEndpointWhenRPCFails() async throws {
        let httpClient = CountingMachineHTTPClient(
            responseData: Data(
                """
                {
                  "models": ["claude-sonnet-4-5"],
                  "reasoningEfforts": ["high"]
                }
                """.utf8
            ),
            statusCode: 200
        )
        let rpcDirectoryService = NoopMachineRPCDirectoryService(
            invokeCommandResult: .failure(MachinesAPIError.rpcTimedOut)
        )
        let service = URLSessionMachinesService(
            httpClient: httpClient,
            rpcDirectoryService: rpcDirectoryService
        )

        let capabilities = try await service.fetchAgentCapabilities(
            serverURL: URL(string: "https://api.unhappy.im")!,
            token: "token",
            machineID: "machine-1",
            agent: .claude
        )

        #expect(capabilities.models == ["claude-sonnet-4-5"])
        #expect(capabilities.reasoningEfforts == ["high"])
        #expect(await httpClient.requestCount == 1)
        #expect(await rpcDirectoryService.invokedCommands == ["list-models"])
    }
}

private actor CountingMachineHTTPClient: MachineHTTPClient {
    let responseData: Data
    let statusCode: Int
    private(set) var requestCount = 0

    init(responseData: Data, statusCode: Int = 200) {
        self.responseData = responseData
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        return (
            responseData,
            HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.unhappy.im")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}

private actor NoopMachineRPCDirectoryService: MachineRPCDirectoryListing {
    private let invokeCommandResult: Result<Data, Error>
    private(set) var invokedCommands: [String] = []

    init(invokeCommandResult: Result<Data, Error> = .success(Data())) {
        self.invokeCommandResult = invokeCommandResult
    }

    func fetchProjects(
        serverURL: URL,
        token: String,
        machineID: String,
        explicitOnly: Bool,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> [APIMachineProjectSummary] {
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
        APIProjectSessionsPage(sessions: [], nextCursor: nil, hasNext: false)
    }

    func openProject(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APIMachineCommandResult {
        APIMachineCommandResult(success: true, message: "ok", error: nil)
    }

    func removeProject(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APIMachineCommandResult {
        APIMachineCommandResult(success: true, message: "ok", error: nil)
    }

    func spawnProviderSession(_ request: MachineSessionSpawnServiceRequest) async throws -> APISessionSpawnResult {
        APISessionSpawnResult(success: true, sessionID: "session", requiresUserApproval: nil, actionRequired: nil, directory: nil, error: nil)
    }

    func listDirectory(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        machineDataEncryptionKey: String?
    ) async throws -> APIMachineListDirectoryResult {
        APIMachineListDirectoryResult(success: true, entries: [], error: nil)
    }

    func readFile(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APISessionReadFileResult {
        APISessionReadFileResult(success: true, content: nil, error: nil)
    }

    func runBash(
        serverURL: URL,
        token: String,
        machineID: String,
        command: String,
        cwd: String,
        wrappedMachineDataEncryptionKey: String?,
        timeoutMilliseconds: Int
    ) async throws -> APISessionBashResult {
        APISessionBashResult(success: true, stdout: "", stderr: "", exitCode: 0, error: nil)
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
        APICodexThreadsPage(threads: [], nextCursor: nil, hasNext: false)
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
        APIClaudeSessionsPage(sessions: [], nextCursor: nil, hasNext: false)
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
        APIGeminiSessionsPage(sessions: [], nextCursor: nil, hasNext: false)
    }

    func fetchCodexThreadMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        threadID: String,
        transcriptPath: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        APISessionMessagesPage(messages: [], nextCursor: nil, hasNext: false)
    }

    func sendCodexThreadMessage(
        serverURL: URL,
        token: String,
        machineID: String,
        threadID: String,
        cwd: String,
        transcriptPath: String?,
        wrappedMachineDataEncryptionKey: String?,
        model: String?,
        reasoningEffort: APISessionReasoningEffort?,
        permissionMode: APISessionMessagePermissionMode?,
        text: String
    ) async throws -> APISessionSendMessageResult {
        APISessionSendMessageResult(success: true, queueCount: nil, queuedMessages: nil, error: nil)
    }

    func fetchClaudeSessionMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        cwd: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        APISessionMessagesPage(messages: [], nextCursor: nil, hasNext: false)
    }

    func sendClaudeSessionMessage(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        cwd: String,
        wrappedMachineDataEncryptionKey: String?,
        model: String?,
        reasoningEffort: APISessionReasoningEffort?,
        permissionMode: APISessionMessagePermissionMode?,
        text: String
    ) async throws -> APISessionSendMessageResult {
        APISessionSendMessageResult(success: true, queueCount: nil, queuedMessages: nil, error: nil)
    }

    func fetchGeminiSessionMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        APISessionMessagesPage(messages: [], nextCursor: nil, hasNext: false)
    }

    func sendGeminiSessionMessage(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        wrappedMachineDataEncryptionKey: String?,
        model: String?,
        permissionMode: APISessionMessagePermissionMode?,
        text: String
    ) async throws -> APISessionSendMessageResult {
        APISessionSendMessageResult(success: true, queueCount: nil, queuedMessages: nil, error: nil)
    }

    func invokeCommand(
        serverURL: URL,
        token: String,
        machineID: String,
        command: String,
        params: [String : RPCParameterValue]
    ) async throws -> Data {
        invokedCommands.append(command)
        return try invokeCommandResult.get()
    }
}

private actor CountingProjectRPCDirectoryService: MachineRPCDirectoryListing {
    let projects: [APIMachineProjectSummary]
    private(set) var fetchProjectsCount = 0

    init(projects: [APIMachineProjectSummary]) {
        self.projects = projects
    }

    func fetchProjects(
        serverURL: URL,
        token: String,
        machineID: String,
        explicitOnly: Bool,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> [APIMachineProjectSummary] {
        fetchProjectsCount += 1
        return projects
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
        APIProjectSessionsPage(sessions: [], nextCursor: nil, hasNext: false)
    }

    func openProject(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APIMachineCommandResult {
        APIMachineCommandResult(success: true, message: "ok", error: nil)
    }

    func removeProject(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APIMachineCommandResult {
        APIMachineCommandResult(success: true, message: "ok", error: nil)
    }

    func spawnProviderSession(_ request: MachineSessionSpawnServiceRequest) async throws -> APISessionSpawnResult {
        APISessionSpawnResult(success: true, sessionID: "session", requiresUserApproval: nil, actionRequired: nil, directory: nil, error: nil)
    }

    func listDirectory(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        machineDataEncryptionKey: String?
    ) async throws -> APIMachineListDirectoryResult {
        APIMachineListDirectoryResult(success: true, entries: [], error: nil)
    }

    func readFile(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APISessionReadFileResult {
        APISessionReadFileResult(success: true, content: nil, error: nil)
    }

    func runBash(
        serverURL: URL,
        token: String,
        machineID: String,
        command: String,
        cwd: String,
        wrappedMachineDataEncryptionKey: String?,
        timeoutMilliseconds: Int
    ) async throws -> APISessionBashResult {
        APISessionBashResult(success: true, stdout: "", stderr: "", exitCode: 0, error: nil)
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
        APICodexThreadsPage(threads: [], nextCursor: nil, hasNext: false)
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
        APIClaudeSessionsPage(sessions: [], nextCursor: nil, hasNext: false)
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
        APIGeminiSessionsPage(sessions: [], nextCursor: nil, hasNext: false)
    }

    func fetchCodexThreadMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        threadID: String,
        transcriptPath: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        APISessionMessagesPage(messages: [], nextCursor: nil, hasNext: false)
    }

    func sendCodexThreadMessage(
        serverURL: URL,
        token: String,
        machineID: String,
        threadID: String,
        cwd: String,
        transcriptPath: String?,
        wrappedMachineDataEncryptionKey: String?,
        model: String?,
        reasoningEffort: APISessionReasoningEffort?,
        permissionMode: APISessionMessagePermissionMode?,
        text: String
    ) async throws -> APISessionSendMessageResult {
        APISessionSendMessageResult(success: true, queueCount: nil, queuedMessages: nil, error: nil)
    }

    func fetchClaudeSessionMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        cwd: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        APISessionMessagesPage(messages: [], nextCursor: nil, hasNext: false)
    }

    func sendClaudeSessionMessage(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        cwd: String,
        wrappedMachineDataEncryptionKey: String?,
        model: String?,
        reasoningEffort: APISessionReasoningEffort?,
        permissionMode: APISessionMessagePermissionMode?,
        text: String
    ) async throws -> APISessionSendMessageResult {
        APISessionSendMessageResult(success: true, queueCount: nil, queuedMessages: nil, error: nil)
    }

    func fetchGeminiSessionMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        APISessionMessagesPage(messages: [], nextCursor: nil, hasNext: false)
    }

    func sendGeminiSessionMessage(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        wrappedMachineDataEncryptionKey: String?,
        model: String?,
        permissionMode: APISessionMessagePermissionMode?,
        text: String
    ) async throws -> APISessionSendMessageResult {
        APISessionSendMessageResult(success: true, queueCount: nil, queuedMessages: nil, error: nil)
    }

    func invokeCommand(
        serverURL: URL,
        token: String,
        machineID: String,
        command: String,
        params: [String : RPCParameterValue]
    ) async throws -> Data {
        Data()
    }
}

private actor PrewarmingMachineRPCDirectoryService: MachineRPCDirectoryListing {
    private(set) var prewarmedMachineIDs: [String] = []

    func prewarmMachineDataPlane(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?
    ) async {
        prewarmedMachineIDs.append(machineID)
    }

    func fetchProjects(
        serverURL: URL,
        token: String,
        machineID: String,
        explicitOnly: Bool,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> [APIMachineProjectSummary] {
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
        APIProjectSessionsPage(sessions: [], nextCursor: nil, hasNext: false)
    }

    func openProject(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APIMachineCommandResult {
        APIMachineCommandResult(success: true, message: "ok", error: nil)
    }

    func removeProject(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APIMachineCommandResult {
        APIMachineCommandResult(success: true, message: "ok", error: nil)
    }

    func spawnProviderSession(_ request: MachineSessionSpawnServiceRequest) async throws -> APISessionSpawnResult {
        APISessionSpawnResult(success: true, sessionID: "session", requiresUserApproval: nil, actionRequired: nil, directory: nil, error: nil)
    }

    func listDirectory(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        machineDataEncryptionKey: String?
    ) async throws -> APIMachineListDirectoryResult {
        APIMachineListDirectoryResult(success: true, entries: [], error: nil)
    }

    func readFile(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APISessionReadFileResult {
        APISessionReadFileResult(success: true, content: nil, error: nil)
    }

    func runBash(
        serverURL: URL,
        token: String,
        machineID: String,
        command: String,
        cwd: String,
        wrappedMachineDataEncryptionKey: String?,
        timeoutMilliseconds: Int
    ) async throws -> APISessionBashResult {
        APISessionBashResult(success: true, stdout: "", stderr: "", exitCode: 0, error: nil)
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
        APICodexThreadsPage(threads: [], nextCursor: nil, hasNext: false)
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
        APIClaudeSessionsPage(sessions: [], nextCursor: nil, hasNext: false)
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
        APIGeminiSessionsPage(sessions: [], nextCursor: nil, hasNext: false)
    }

    func fetchCodexThreadMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        threadID: String,
        transcriptPath: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        APISessionMessagesPage(messages: [], nextCursor: nil, hasNext: false)
    }

    func sendCodexThreadMessage(
        serverURL: URL,
        token: String,
        machineID: String,
        threadID: String,
        cwd: String,
        transcriptPath: String?,
        wrappedMachineDataEncryptionKey: String?,
        model: String?,
        reasoningEffort: APISessionReasoningEffort?,
        permissionMode: APISessionMessagePermissionMode?,
        text: String
    ) async throws -> APISessionSendMessageResult {
        APISessionSendMessageResult(success: true, queueCount: nil, queuedMessages: nil, error: nil)
    }

    func fetchClaudeSessionMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        cwd: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        APISessionMessagesPage(messages: [], nextCursor: nil, hasNext: false)
    }

    func sendClaudeSessionMessage(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        cwd: String,
        wrappedMachineDataEncryptionKey: String?,
        model: String?,
        reasoningEffort: APISessionReasoningEffort?,
        permissionMode: APISessionMessagePermissionMode?,
        text: String
    ) async throws -> APISessionSendMessageResult {
        APISessionSendMessageResult(success: true, queueCount: nil, queuedMessages: nil, error: nil)
    }

    func fetchGeminiSessionMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        APISessionMessagesPage(messages: [], nextCursor: nil, hasNext: false)
    }

    func sendGeminiSessionMessage(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        wrappedMachineDataEncryptionKey: String?,
        model: String?,
        permissionMode: APISessionMessagePermissionMode?,
        text: String
    ) async throws -> APISessionSendMessageResult {
        APISessionSendMessageResult(success: true, queueCount: nil, queuedMessages: nil, error: nil)
    }

    func invokeCommand(
        serverURL: URL,
        token: String,
        machineID: String,
        command: String,
        params: [String : RPCParameterValue]
    ) async throws -> Data {
        Data()
    }
}
