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
}

private actor CountingMachineHTTPClient: MachineHTTPClient {
    let responseData: Data
    private(set) var requestCount = 0

    init(responseData: Data) {
        self.responseData = responseData
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        return (
            responseData,
            HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.unhappy.im")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}

private actor NoopMachineRPCDirectoryService: MachineRPCDirectoryListing {
    func fetchProjects(
        serverURL: URL,
        token: String,
        machineID: String,
        explicitOnly: Bool,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> [APIMachineProjectSummary] {
        []
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
