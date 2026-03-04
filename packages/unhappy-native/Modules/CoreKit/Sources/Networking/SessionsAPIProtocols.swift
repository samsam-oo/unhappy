import Foundation

public protocol SessionsFetching: Sendable {
    func fetchSessions(serverURL: URL, token: String) async throws -> [APISession]
}

public protocol SessionsPagingFetching: Sendable {
    func fetchSessionsPage(
        serverURL: URL,
        token: String,
        cursor: String?,
        limit: Int
    ) async throws -> APISessionsPage
}

public protocol SessionMessagesFetching: Sendable {
    func fetchSessionMessages(serverURL: URL, token: String, sessionID: String) async throws -> [APISessionMessage]
}

public protocol SessionDeleting: Sendable {
    func deleteSession(serverURL: URL, token: String, sessionID: String) async throws
}

public protocol SessionTitleUpdating: Sendable {
    func setSessionTitle(serverURL: URL, token: String, sessionID: String, title: String?) async throws
}

public protocol SessionCodexThreadsFetching: Sendable {
    func fetchCodexThreads(
        serverURL: URL,
        token: String,
        sessionID: String,
        limit: Int,
        cwd: String?
    ) async throws -> [APICodexThreadSummary]
}

public protocol SessionClaudeSessionsFetching: Sendable {
    func fetchClaudeSessions(
        serverURL: URL,
        token: String,
        sessionID: String,
        limit: Int,
        cwd: String?
    ) async throws -> [APIClaudeSessionSummary]
}

public protocol SessionSpawning: Sendable {
    func spawnSession(
        serverURL: URL,
        token: String,
        sessionID: String,
        directory: String,
        agent: APISessionSpawnAgent?,
        codexResumeThreadID: String?,
        claudeResumeSessionID: String?,
        approvedNewDirectoryCreation: Bool?
    ) async throws -> APISessionSpawnResult
}

public protocol SessionAborting: Sendable {
    func abortSessionTask(
        serverURL: URL,
        token: String,
        sessionID: String,
        reason: String?
    ) async throws -> APISessionCommandResult
}

public protocol SessionPermissionResponding: Sendable {
    func respondPermission(
        serverURL: URL,
        token: String,
        sessionID: String,
        permissionRequestID: String,
        approved: Bool,
        mode: APISessionPermissionMode?,
        allowTools: [String]?,
        decision: APISessionPermissionDecision?
    ) async throws -> APISessionCommandResult
}

public protocol SessionModeSwitching: Sendable {
    func switchSessionMode(
        serverURL: URL,
        token: String,
        sessionID: String,
        to: APISessionSwitchTarget
    ) async throws -> APISessionSwitchResult
}

public protocol SessionMessaging: Sendable {
    func sendMessage(
        serverURL: URL,
        token: String,
        sessionID: String,
        text: String,
        steerMode: APISessionSteerMode?,
        permissionMode: APISessionMessagePermissionMode?,
        model: String?,
        resetModel: Bool,
        reasoningEffort: APISessionReasoningEffort?,
        resetReasoningEffort: Bool
    ) async throws -> APISessionSendMessageResult
}

public protocol SessionBashRunning: Sendable {
    func runBash(
        serverURL: URL,
        token: String,
        sessionID: String,
        command: String,
        cwd: String?,
        timeout: Int?
    ) async throws -> APISessionBashResult
}

public protocol SessionRipgrepRunning: Sendable {
    func runRipgrep(
        serverURL: URL,
        token: String,
        sessionID: String,
        args: [String],
        cwd: String?
    ) async throws -> APISessionBashResult
}

public protocol SessionDifftasticRunning: Sendable {
    func runDifftastic(
        serverURL: URL,
        token: String,
        sessionID: String,
        args: [String],
        cwd: String?
    ) async throws -> APISessionBashResult
}

public protocol SessionFileReading: Sendable {
    func readFile(
        serverURL: URL,
        token: String,
        sessionID: String,
        path: String
    ) async throws -> APISessionReadFileResult
}

public protocol SessionFileWriting: Sendable {
    func writeFile(
        serverURL: URL,
        token: String,
        sessionID: String,
        path: String,
        content: String,
        expectedHash: String?
    ) async throws -> APISessionWriteFileResult
}

public protocol SessionDirectoryListing: Sendable {
    func listDirectory(
        serverURL: URL,
        token: String,
        sessionID: String,
        path: String
    ) async throws -> APISessionListDirectoryResult
}

public protocol SessionKilling: Sendable {
    func killSession(
        serverURL: URL,
        token: String,
        sessionID: String
    ) async throws -> APISessionKillResult
}

public protocol SessionModelsListing: Sendable {
    func fetchAgentCapabilities(
        serverURL: URL,
        token: String,
        sessionID: String,
        agent: APISessionSpawnAgent?
    ) async throws -> APIMachineAgentCapabilities
}
