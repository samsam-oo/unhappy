import Foundation
import SocketIO
import SecurityKit

public enum RPCParameterValue: Sendable, Equatable, ExpressibleByNilLiteral, ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case array([RPCParameterValue])
    case object([String: RPCParameterValue])
    case null

    public init(nilLiteral: ()) {
        self = .null
    }

    public init(stringLiteral value: String) {
        self = .string(value)
    }

    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }

    public init(integerLiteral value: Int) {
        self = .int(value)
    }

    public init(floatLiteral value: Double) {
        self = .double(value)
    }

    public init(arrayLiteral elements: RPCParameterValue...) {
        self = .array(elements)
    }

    public init(dictionaryLiteral elements: (String, RPCParameterValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }

    fileprivate var socketValue: Any {
        switch self {
        case .string(let value):
            return value
        case .bool(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .array(let values):
            return values.map(\.socketValue)
        case .object(let values):
            return values.mapValues(\.socketValue)
        case .null:
            return NSNull()
        }
    }
}

public protocol MachineRPCDirectoryListing: Sendable {
    func invokeCommand(
        serverURL: URL,
        token: String,
        machineID: String,
        command: String,
        params: [String: RPCParameterValue]
    ) async throws -> Data

    func spawnProviderSession(
        _ request: MachineSessionSpawnServiceRequest
    ) async throws -> APISessionSpawnResult

    func listDirectory(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        machineDataEncryptionKey: String?
    ) async throws -> APIMachineListDirectoryResult

    func readFile(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APISessionReadFileResult

    func runBash(
        serverURL: URL,
        token: String,
        machineID: String,
        command: String,
        cwd: String,
        wrappedMachineDataEncryptionKey: String?,
        timeoutMilliseconds: Int
    ) async throws -> APISessionBashResult

    func fetchCodexThreadsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APICodexThreadsPage

    func fetchClaudeSessionsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APIClaudeSessionsPage

    func fetchGeminiSessionsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APIGeminiSessionsPage

    func fetchProjects(
        serverURL: URL,
        token: String,
        machineID: String,
        explicitOnly: Bool,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> [APIMachineProjectSummary]

    func openProject(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APIMachineCommandResult

    func removeProject(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APIMachineCommandResult

    func fetchCodexThreadMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        threadID: String,
        transcriptPath: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage

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
    ) async throws -> APISessionSendMessageResult

    func fetchClaudeSessionMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        cwd: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage

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
    ) async throws -> APISessionSendMessageResult

    func fetchGeminiSessionMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage

    func sendGeminiSessionMessage(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        wrappedMachineDataEncryptionKey: String?,
        model: String?,
        permissionMode: APISessionMessagePermissionMode?,
        text: String
    ) async throws -> APISessionSendMessageResult
}

public actor SocketIOMachineRPCDirectoryService: MachineRPCDirectoryListing {
    private let connectTimeoutSeconds: Double
    private let ackTimeoutSeconds: Double
    private let dataPlaneClient: MachineDataPlaneWebSocketClient
    private var liveConnection: LiveConnection?
    private let retryableMessageLoadCommands: Set<String> = [
        "codex-list-messages",
        "claude-list-messages",
        "gemini-list-messages",
    ]

    private struct LiveConnection {
        let serverURLString: String
        let token: String
        let manager: SocketManager
        let socket: SocketIOClient
    }

    private enum SocketAckPayload: Sendable, Equatable {
        case noAck
        case json(Data)
    }

    public init(
        connectTimeoutSeconds: Double = 8,
        ackTimeoutSeconds: Double = 30,
        dataPlaneClient: MachineDataPlaneWebSocketClient = MachineDataPlaneWebSocketClient()
    ) {
        self.connectTimeoutSeconds = connectTimeoutSeconds
        self.ackTimeoutSeconds = ackTimeoutSeconds
        self.dataPlaneClient = dataPlaneClient
    }

    public func listDirectory(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        machineDataEncryptionKey: String?
    ) async throws -> APIMachineListDirectoryResult {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }

        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw MachinesAPIError.missingPath
        }

        let responseData = try await dataPlaneClient.requestJSON(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: machineDataEncryptionKey,
            operation: .fsListDirectory,
            bodyObject: [
                "path": normalizedPath,
                "includeStats": false,
                "types": ["directory"],
                "sort": true,
                "maxEntries": 2_000,
            ]
        )
        let decoded = try MachinesAPI.decodeListDirectoryResponse(responseData)
        if decoded.success {
            return decoded
        }

        let normalizedError = decoded.error?.trimmingCharacters(in: .whitespacesAndNewlines)
        throw MachinesAPIError.rpcCallFailed(
            (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "RPC call failed"
        )
    }

    public func spawnProviderSession(
        _ request: MachineSessionSpawnServiceRequest
    ) async throws -> APISessionSpawnResult {
        let normalizedMachineID = request.machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }

        let responseData = try await dataPlaneClient.requestJSON(
            serverURL: request.serverURL,
            token: request.token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: request.wrappedMachineDataEncryptionKey,
            operation: .providerSpawn,
            bodyObject: MachineSessionSpawnRPCParametersBuilder().build(from: request).mapValues(\.socketValue)
        )
        return try MachineSessionSpawnRPCResponseParser.parse(responseData)
    }

    public func fetchCodexThreadsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APICodexThreadsPage {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }

        let boundedLimit = min(max(limit, 1), 100)
        var params: [String: RPCParameterValue] = [
            "limit": .int(boundedLimit),
        ]
        let normalizedCWD = cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCWD, !normalizedCWD.isEmpty {
            params["cwd"] = .string(normalizedCWD)
        }
        let normalizedCursor = cursor?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCursor, !normalizedCursor.isEmpty {
            params["cursor"] = .string(normalizedCursor)
        }

        let responseData = try await dataPlaneClient.requestJSON(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            operation: .codexListThreads,
            bodyObject: params.mapValues(\.socketValue)
        )
        let raw = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        if raw?["success"] as? Bool == false {
            let normalizedError = (raw?["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MachinesAPIError.rpcCallFailed(
                (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "RPC call failed"
            )
        }
        return try MachinesAPI.decodeCodexThreadsPageResponse(responseData)
    }

    public func fetchClaudeSessionsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APIClaudeSessionsPage {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }

        let boundedLimit = min(max(limit, 1), 100)
        var params: [String: RPCParameterValue] = [
            "limit": .int(boundedLimit),
        ]
        let normalizedCWD = cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCWD, !normalizedCWD.isEmpty {
            params["cwd"] = .string(normalizedCWD)
        }
        let normalizedCursor = cursor?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCursor, !normalizedCursor.isEmpty {
            params["cursor"] = .string(normalizedCursor)
        }

        let responseData = try await dataPlaneClient.requestJSON(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            operation: .claudeListSessions,
            bodyObject: params.mapValues(\.socketValue)
        )
        let raw = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        if raw?["success"] as? Bool == false {
            let normalizedError = (raw?["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MachinesAPIError.rpcCallFailed(
                (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "RPC call failed"
            )
        }
        return try MachinesAPI.decodeClaudeSessionsPageResponse(responseData)
    }

    public func fetchGeminiSessionsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APIGeminiSessionsPage {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }

        let boundedLimit = min(max(limit, 1), 100)
        var params: [String: RPCParameterValue] = [
            "limit": .int(boundedLimit),
        ]
        let normalizedCWD = cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCWD, !normalizedCWD.isEmpty {
            params["cwd"] = .string(normalizedCWD)
        }
        let normalizedCursor = cursor?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCursor, !normalizedCursor.isEmpty {
            params["cursor"] = .string(normalizedCursor)
        }

        let responseData = try await dataPlaneClient.requestJSON(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            operation: .geminiListSessions,
            bodyObject: params.mapValues(\.socketValue)
        )
        return try MachinesAPI.decodeGeminiSessionsPageResponse(responseData)
    }

    public func fetchProjects(
        serverURL: URL,
        token: String,
        machineID: String,
        explicitOnly: Bool,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> [APIMachineProjectSummary] {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }

        let responseData = try await dataPlaneClient.requestJSON(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            operation: .projectList,
            bodyObject: [
                "explicitOnly": explicitOnly,
            ]
        )
        return try MachinesAPI.decodeProjectsResponse(responseData)
    }

    public func openProject(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APIMachineCommandResult {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw MachinesAPIError.missingPath
        }

        let responseData = try await dataPlaneClient.requestJSON(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            operation: .projectOpen,
            bodyObject: [
                "path": normalizedPath,
            ]
        )
        return try JSONDecoder().decode(APIMachineCommandResult.self, from: responseData)
    }

    public func removeProject(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APIMachineCommandResult {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw MachinesAPIError.missingPath
        }

        let responseData = try await dataPlaneClient.requestJSON(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            operation: .projectRemove,
            bodyObject: [
                "path": normalizedPath,
            ]
        )
        return try JSONDecoder().decode(APIMachineCommandResult.self, from: responseData)
    }

    public func invokeCommand(
        serverURL: URL,
        token: String,
        machineID: String,
        command: String,
        params: [String: RPCParameterValue]
    ) async throws -> Data {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }

        let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCommand.isEmpty else {
            throw MachinesAPIError.missingCommand
        }
        let operation: MachineDataPlaneOperation
        switch normalizedCommand {
        case "list-models":
            operation = .machineListModels
        case "stop-daemon":
            operation = .daemonStop
        case "update-daemon":
            operation = .daemonUpdate
        default:
            throw MachinesAPIError.rpcCallFailed("Unsupported machine command: \(normalizedCommand)")
        }

        let wrappedMachineDataEncryptionKey = try await fetchWrappedMachineDataEncryptionKey(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID
        )

        return try await dataPlaneClient.requestJSON(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            operation: operation,
            bodyObject: params.mapValues(\.socketValue)
        )
    }

    private func invokeSensitiveCommand(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        command: String,
        params: [String: RPCParameterValue]
    ) async throws -> Data {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw MachinesAPIError.missingToken
        }
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCommand.isEmpty else {
            throw MachinesAPIError.missingCommand
        }

        guard let operation = dataPlaneOperation(for: normalizedCommand) else {
            throw MachinesAPIError.rpcCallFailed("Unsupported machine data-plane command: \(normalizedCommand)")
        }

        return try await dataPlaneClient.requestJSON(
            serverURL: serverURL,
            token: normalizedToken,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            operation: operation,
            bodyObject: params.mapValues(\.socketValue)
        )
    }

    private func dataPlaneOperation(for command: String) -> MachineDataPlaneOperation? {
        switch command {
        case "list-models":
            return .machineListModels
        case "stop-daemon":
            return .daemonStop
        case "update-daemon":
            return .daemonUpdate
        case "spawn-provider-session":
            return .providerSpawn
        case "list-projects":
            return .projectList
        case "open-project":
            return .projectOpen
        case "close-project":
            return .projectRemove
        case "codex-list-threads":
            return .codexListThreads
        case "codex-open-thread":
            return .codexOpenThread
        case "codex-list-messages":
            return .codexListMessages
        case "codex-send-message":
            return .codexSendMessage
        case "claude-list-sessions":
            return .claudeListSessions
        case "claude-list-messages":
            return .claudeListMessages
        case "claude-send-message":
            return .claudeSendMessage
        case "gemini-list-sessions":
            return .geminiListSessions
        case "gemini-list-messages":
            return .geminiListMessages
        case "gemini-send-message":
            return .geminiSendMessage
        case "listDirectory":
            return .fsListDirectory
        case "getDirectoryTree":
            return .fsGetDirectoryTree
        case "readFile":
            return .fsReadFile
        case "writeFile":
            return .fsWriteFile
        case "bash":
            return .execBash
        case "ripgrep":
            return .searchRipgrep
        case "difftastic":
            return .diffDifftastic
        default:
            return nil
        }
    }

    public func fetchCodexThreadMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        threadID: String,
        transcriptPath: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let normalizedThreadID = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedThreadID.isEmpty else {
            throw MachinesAPIError.rpcCallFailed("Thread ID is required")
        }
        let normalizedPath = transcriptPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw MachinesAPIError.missingPath
        }

        let requestBody: [String: Any] = [
            "threadId": normalizedThreadID,
            "path": normalizedPath,
            "limit": limit,
            "cursor": cursor ?? NSNull(),
        ]

        let responseData = try await dataPlaneClient.requestJSON(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            operation: .codexListMessages,
            bodyObject: requestBody
        )
        return try decodeSessionMessagesPage(responseData)
    }

    public func readFile(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APISessionReadFileResult {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw MachinesAPIError.missingPath
        }

        let responseData = try await dataPlaneClient.requestJSON(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            operation: .fsReadFile,
            bodyObject: [
                "path": normalizedPath,
            ]
        )
        let decoder = JSONDecoder()
        return try decoder.decode(APISessionReadFileResult.self, from: responseData)
    }

    public func runBash(
        serverURL: URL,
        token: String,
        machineID: String,
        command: String,
        cwd: String,
        wrappedMachineDataEncryptionKey: String?,
        timeoutMilliseconds: Int
    ) async throws -> APISessionBashResult {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCommand.isEmpty else {
            throw MachinesAPIError.missingCommand
        }
        let normalizedCWD = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCWD.isEmpty else {
            throw MachinesAPIError.missingPath
        }

        let responseData = try await dataPlaneClient.requestJSON(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            operation: .execBash,
            bodyObject: [
                "command": normalizedCommand,
                "cwd": normalizedCWD,
                "timeout": max(timeoutMilliseconds, 1_000),
            ]
        )
        let decoder = JSONDecoder()
        return try decoder.decode(APISessionBashResult.self, from: responseData)
    }

    public func sendCodexThreadMessage(
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
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let normalizedThreadID = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedThreadID.isEmpty else {
            throw MachinesAPIError.rpcCallFailed("Thread ID is required")
        }
        let normalizedCWD = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCWD.isEmpty else {
            throw MachinesAPIError.missingPath
        }
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw MachinesAPIError.missingCommand
        }

        var params: [String: RPCParameterValue] = [
            "threadId": .string(normalizedThreadID),
            "cwd": .string(normalizedCWD),
            "text": .string(normalizedText),
        ]
        let normalizedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedModel, !normalizedModel.isEmpty {
            params["model"] = .string(normalizedModel)
        }
        if let reasoningEffort {
            params["effort"] = .string(reasoningEffort.rawValue)
        }
        if let permissionMode {
            params["permissionMode"] = .string(permissionMode.rawValue)
        }
        let normalizedPath = transcriptPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedPath, !normalizedPath.isEmpty {
            params["path"] = .string(normalizedPath)
        }

        let responseData = try await dataPlaneClient.requestJSON(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            operation: .codexSendMessage,
            bodyObject: params.mapValues(\.socketValue)
        )
        let decoder = JSONDecoder()
        return try decoder.decode(APISessionSendMessageResult.self, from: responseData)
    }

    public func fetchClaudeSessionMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        cwd: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw MachinesAPIError.rpcCallFailed("Session ID is required")
        }
        let normalizedCWD = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCWD.isEmpty else {
            throw MachinesAPIError.missingPath
        }

        let responseData = try await dataPlaneClient.requestJSON(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            operation: .claudeListMessages,
            bodyObject: [
                "sessionId": normalizedSessionID,
                "cwd": normalizedCWD,
                "limit": limit,
                "cursor": cursor.map { $0 as Any } ?? NSNull(),
            ]
        )
        return try decodeSessionMessagesPage(responseData)
    }

    public func sendClaudeSessionMessage(
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
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw MachinesAPIError.rpcCallFailed("Session ID is required")
        }
        let normalizedCWD = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCWD.isEmpty else {
            throw MachinesAPIError.missingPath
        }
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw MachinesAPIError.missingCommand
        }

        var params: [String: RPCParameterValue] = [
            "sessionId": .string(normalizedSessionID),
            "cwd": .string(normalizedCWD),
            "text": .string(normalizedText),
        ]
        let normalizedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedModel, !normalizedModel.isEmpty {
            params["model"] = .string(normalizedModel)
        }
        if let reasoningEffort {
            params["effort"] = .string(reasoningEffort.rawValue)
        }
        if let permissionMode {
            params["permissionMode"] = .string(permissionMode.rawValue)
        }

        let responseData = try await dataPlaneClient.requestJSON(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            operation: .claudeSendMessage,
            bodyObject: params.mapValues(\.socketValue)
        )
        let decoder = JSONDecoder()
        return try decoder.decode(APISessionSendMessageResult.self, from: responseData)
    }

    public func fetchGeminiSessionMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw MachinesAPIError.rpcCallFailed("Session ID is required")
        }

        let responseData = try await dataPlaneClient.requestJSON(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            operation: .geminiListMessages,
            bodyObject: [
                "sessionId": normalizedSessionID,
                "limit": limit,
                "cursor": cursor.map { $0 as Any } ?? NSNull(),
            ]
        )
        return try decodeSessionMessagesPage(responseData)
    }

    public func sendGeminiSessionMessage(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        wrappedMachineDataEncryptionKey: String?,
        model: String?,
        permissionMode: APISessionMessagePermissionMode?,
        text: String
    ) async throws -> APISessionSendMessageResult {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw MachinesAPIError.rpcCallFailed("Session ID is required")
        }
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw MachinesAPIError.missingCommand
        }

        var params: [String: RPCParameterValue] = [
            "sessionId": .string(normalizedSessionID),
            "text": .string(normalizedText),
        ]
        let normalizedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedModel, !normalizedModel.isEmpty {
            params["model"] = .string(normalizedModel)
        }
        if let permissionMode {
            params["permissionMode"] = .string(permissionMode.rawValue)
        }

        let responseData = try await dataPlaneClient.requestJSON(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            operation: .geminiSendMessage,
            bodyObject: params.mapValues(\.socketValue)
        )
        let decoder = JSONDecoder()
        return try decoder.decode(APISessionSendMessageResult.self, from: responseData)
    }

    private func getOrCreateConnectedSocket(
        serverURL: URL,
        token: String
    ) async throws -> SocketIOClient {
        let serverURLString = serverURL.absoluteString

        if let liveConnection {
            let sameIdentity =
                liveConnection.serverURLString == serverURLString &&
                liveConnection.token == token
            if sameIdentity, liveConnection.socket.status == .connected {
                return liveConnection.socket
            }
            teardownLiveConnection()
        }

        let queue = DispatchQueue(label: "im.unhappy.native.machine-rpc.\(UUID().uuidString)")
        let manager = SocketManager(
            socketURL: serverURL,
            config: [
                .path("/v1/updates"),
                .version(.three),
                .forceWebsockets(true),
                .reconnects(false),
                .log(false),
                .compress,
                .handleQueue(queue),
            ]
        )
        let socket = manager.defaultSocket
        do {
            try await connectSocket(socket, token: token)
        } catch {
            socket.disconnect()
            manager.disconnect()
            throw error
        }

        liveConnection = LiveConnection(
            serverURLString: serverURLString,
            token: token,
            manager: manager,
            socket: socket
        )
        return socket
    }

    private func teardownLiveConnection() {
        guard let liveConnection else { return }
        liveConnection.socket.disconnect()
        liveConnection.manager.disconnect()
        self.liveConnection = nil
    }

    private func connectSocket(_ socket: SocketIOClient, token: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var completed = false
            var handlerIDs: [UUID] = []

            func finish(_ result: Result<Void, Error>) {
                guard !completed else { return }
                completed = true
                for handlerID in handlerIDs {
                    socket.off(id: handlerID)
                }
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            handlerIDs.append(
                socket.on(clientEvent: .connect) { _, _ in
                    finish(.success(()))
                }
            )

            handlerIDs.append(
                socket.on(clientEvent: .error) { data, _ in
                    let reason = data.first.map(String.init(describing:)) ?? "Socket connection error"
                    finish(.failure(MachinesAPIError.rpcSocketConnectionFailed(reason)))
                }
            )

            handlerIDs.append(
                socket.on(clientEvent: .disconnect) { data, _ in
                    guard !completed else { return }
                    let reason = data.first.map(String.init(describing:)) ?? "Socket disconnected"
                    finish(.failure(MachinesAPIError.rpcSocketConnectionFailed(reason)))
                }
            )

            socket.connect(
                withPayload: [
                    "token": token,
                    "clientType": "user-scoped",
                ],
                timeoutAfter: connectTimeoutSeconds
            ) {
                finish(.failure(MachinesAPIError.rpcSocketConnectionFailed("Connection timeout")))
            }
        }
    }

    private func emitWithAck(
        socket: SocketIOClient,
        event: String,
        payload: [String: Any]
    ) async throws -> SocketAckPayload {
        try await withCheckedThrowingContinuation { continuation in
            socket.rawEmitView
                .emitWithAck(event, with: [payload])
                .timingOut(after: ackTimeoutSeconds) { items in
                    if let first = items.first as? String,
                       first == SocketAckStatus.noAck.rawValue {
                        continuation.resume(returning: .noAck)
                        return
                    }
                    guard let first = items.first,
                          JSONSerialization.isValidJSONObject(first),
                          let data = try? JSONSerialization.data(withJSONObject: first) else {
                        continuation.resume(throwing: MachinesAPIError.invalidRPCPayload)
                        return
                    }
                    continuation.resume(returning: .json(data))
                }
        }
    }

    private func shouldRetryMessageLoad(_ error: Error) -> Bool {
        guard let apiError = error as? MachinesAPIError else {
            return false
        }
        switch apiError {
        case .rpcTimedOut, .rpcSocketConnectionFailed:
            return true
        default:
            return false
        }
    }

    private struct MachineRecordEnvelope: Decodable, Sendable {
        let machine: APIMachine
    }

    private func fetchWrappedMachineDataEncryptionKey(
        serverURL: URL,
        token: String,
        machineID: String
    ) async throws -> String {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw MachinesAPIError.missingToken
        }
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }

        let url = serverURL.appending(path: "v1/machines/\(normalizedMachineID)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(normalizedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MachinesAPIError.invalidRPCPayload
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404 {
                throw MachinesAPIError.machineNotFound(normalizedMachineID)
            }
            let errorMessage = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw MachinesAPIError.rpcCallFailed(
                (errorMessage?.isEmpty == false ? errorMessage : nil) ?? "Failed to resolve machine encryption key"
            )
        }

        let envelope = try JSONDecoder().decode(MachineRecordEnvelope.self, from: data)
        guard let wrappedKey = envelope.machine.dataEncryptionKey?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !wrappedKey.isEmpty else {
            throw MachinesAPIError.rpcCallFailed("Machine data encryption key is unavailable")
        }
        return wrappedKey
    }

    private func decodeSessionMessagesPage(_ data: Data) throws -> APISessionMessagesPage {
        let decoder = JSONDecoder()
        let response = try decoder.decode(SessionMessagesPageEnvelope.self, from: data)
        guard response.success else {
            let normalizedError = response.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MachinesAPIError.rpcCallFailed(
                (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "RPC call failed"
            )
        }
        return APISessionMessagesPage(
            messages: response.messages,
            nextCursor: response.nextCursor,
            hasNext: response.hasNext
        )
    }
}

private struct SessionMessagesPageEnvelope: Decodable {
    let success: Bool
    let messages: [APISessionMessage]
    let nextCursor: String?
    let hasNext: Bool
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case success
        case messages
        case nextCursor
        case hasNext
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = (try? container.decode(Bool.self, forKey: .success)) ?? false
        messages = (try? container.decode([APISessionMessage].self, forKey: .messages)) ?? []
        nextCursor = try? container.decodeIfPresent(String.self, forKey: .nextCursor)
        hasNext = (try? container.decode(Bool.self, forKey: .hasNext)) ?? (nextCursor != nil)
        error = try? container.decodeIfPresent(String.self, forKey: .error)
    }
}
