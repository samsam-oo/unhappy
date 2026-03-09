import Foundation
import SocketIO

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
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> [APISessionMessage]

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
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> [APISessionMessage]

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
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> [APISessionMessage]

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
        ackTimeoutSeconds: Double = 30
    ) {
        self.connectTimeoutSeconds = connectTimeoutSeconds
        self.ackTimeoutSeconds = ackTimeoutSeconds
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

        let responseData = try await invokeSensitiveCommand(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: machineDataEncryptionKey,
            command: "listDirectory",
            params: [
                "path": .string(normalizedPath),
                "includeStats": .bool(false),
                "types": .array([.string("directory")]),
                "sort": .bool(true),
                "maxEntries": .int(2_000),
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

        let responseData = try await invokeSensitiveCommand(
            serverURL: request.serverURL,
            token: request.token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: request.wrappedMachineDataEncryptionKey,
            command: "spawn-provider-session",
            params: MachineSessionSpawnRPCParametersBuilder().build(from: request)
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

        let responseData = try await invokeSensitiveCommand(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            command: "codex-list-threads",
            params: params
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

        let responseData = try await invokeSensitiveCommand(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            command: "claude-list-sessions",
            params: params
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

        let responseData = try await invokeSensitiveCommand(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            command: "gemini-list-sessions",
            params: params
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

        let responseData = try await invokeSensitiveCommand(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            command: "list-projects",
            params: [
                "explicitOnly": .bool(explicitOnly),
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

        let responseData = try await invokeSensitiveCommand(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            command: "open-project",
            params: [
                "path": .string(normalizedPath),
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

        let responseData = try await invokeSensitiveCommand(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            command: "close-project",
            params: [
                "path": .string(normalizedPath),
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

        let requestPayload: [String: Any] = [
            "machineId": normalizedMachineID,
            "command": normalizedCommand,
            "params": params.mapValues(\.socketValue),
        ]

        let maxAttempts = retryableMessageLoadCommands.contains(normalizedCommand) ? 2 : 1
        var lastError: Error?

        for attempt in 0..<maxAttempts {
            let socket = try await getOrCreateConnectedSocket(
                serverURL: serverURL,
                token: normalizedToken
            )

            do {
                let ackPayload = try await emitWithAck(
                    socket: socket,
                    event: "machine-public-command",
                    payload: requestPayload
                )

                if ackPayload == .noAck {
                    teardownLiveConnection()
                    throw MachinesAPIError.rpcTimedOut
                }

                guard case .json(let responseData) = ackPayload,
                      let responseObject = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
                    teardownLiveConnection()
                    throw MachinesAPIError.invalidRPCPayload
                }

                if responseObject["success"] as? Bool == false,
                   retryableMessageLoadCommands.contains(normalizedCommand),
                   let errorMessage = (responseObject["error"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased(),
                   errorMessage.contains("timed out") {
                    teardownLiveConnection()
                    lastError = MachinesAPIError.rpcCallFailed(errorMessage)
                    let shouldRetry = attempt < maxAttempts - 1
                    if shouldRetry {
                        try? await Task.sleep(nanoseconds: 750_000_000)
                        continue
                    }
                }

                return try JSONSerialization.data(withJSONObject: responseObject)
            } catch {
                teardownLiveConnection()
                lastError = error

                let shouldRetry = attempt < maxAttempts - 1 && shouldRetryMessageLoad(error)
                if shouldRetry {
                    try? await Task.sleep(nanoseconds: 750_000_000)
                    continue
                }
                throw error
            }
        }

        throw lastError ?? MachinesAPIError.rpcTimedOut
    }

    private func invokeSensitiveCommand(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        command: String,
        params: [String: RPCParameterValue]
    ) async throws -> Data {
        guard let dataKey = MachineDataPlaneEncryption.resolveMachineDataKey(
            rawWrappedKey: wrappedMachineDataEncryptionKey
        ) else {
            throw MachinesAPIError.rpcCallFailed("Machine data encryption key is unavailable")
        }

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

        let socket = try await getOrCreateConnectedSocket(
            serverURL: serverURL,
            token: normalizedToken
        )

        let encryptedParams = try MachineDataPlaneEncryption.encryptJSONPayload(
            params.mapValues(\.socketValue),
            dataKey: dataKey
        )

        let ackPayload = try await emitWithAck(
            socket: socket,
            event: "rpc-call",
            payload: [
                "method": "\(normalizedMachineID):\(normalizedCommand)",
                "params": encryptedParams,
            ]
        )

        if ackPayload == .noAck {
            teardownLiveConnection()
            throw MachinesAPIError.rpcTimedOut
        }

        guard case .json(let ackData) = ackPayload,
              let responseObject = try? JSONSerialization.jsonObject(with: ackData) as? [String: Any] else {
            teardownLiveConnection()
            throw MachinesAPIError.invalidRPCPayload
        }

        guard let ok = responseObject["ok"] as? Bool else {
            teardownLiveConnection()
            throw MachinesAPIError.invalidRPCPayload
        }

        if !ok {
            let message = (responseObject["error"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw MachinesAPIError.rpcCallFailed(
                (message?.isEmpty == false ? message : nil) ?? "Encrypted RPC call failed"
            )
        }

        guard let encryptedResult = responseObject["result"] as? String else {
            throw MachinesAPIError.invalidRPCPayload
        }

        let decryptedData = try MachineDataPlaneEncryption.decryptJSONPayload(
            encryptedResult,
            dataKey: dataKey
        )

        if let object = try? JSONSerialization.jsonObject(with: decryptedData) as? [String: Any],
           let errorMessage = (object["error"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !errorMessage.isEmpty {
            throw MachinesAPIError.rpcCallFailed(errorMessage)
        }

        return decryptedData
    }

    public func fetchCodexThreadMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        threadID: String,
        transcriptPath: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> [APISessionMessage] {
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

        let responseData = try await invokeSensitiveCommand(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            command: "codex-list-messages",
            params: [
                "threadId": .string(normalizedThreadID),
                "path": .string(normalizedPath),
            ]
        )
        let raw = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        if raw?["success"] as? Bool == false {
            let normalizedError = (raw?["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MachinesAPIError.rpcCallFailed(
                (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "RPC call failed"
            )
        }
        let decoder = JSONDecoder()
        return try decoder.decode(CodexThreadMessagesEnvelope.self, from: responseData).messages
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

        let responseData = try await invokeSensitiveCommand(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            command: "readFile",
            params: [
                "path": .string(normalizedPath),
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

        let responseData = try await invokeSensitiveCommand(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            command: "bash",
            params: [
                "command": .string(normalizedCommand),
                "cwd": .string(normalizedCWD),
                "timeout": .int(max(timeoutMilliseconds, 1_000)),
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

        let responseData = try await invokeSensitiveCommand(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            command: "codex-send-message",
            params: params
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
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> [APISessionMessage] {
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

        let responseData = try await invokeSensitiveCommand(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            command: "claude-list-messages",
            params: [
                "sessionId": .string(normalizedSessionID),
                "cwd": .string(normalizedCWD),
            ]
        )
        let raw = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        if raw?["success"] as? Bool == false {
            let normalizedError = (raw?["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MachinesAPIError.rpcCallFailed(
                (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "RPC call failed"
            )
        }
        let decoder = JSONDecoder()
        return try decoder.decode(CodexThreadMessagesEnvelope.self, from: responseData).messages
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

        let responseData = try await invokeSensitiveCommand(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            command: "claude-send-message",
            params: params
        )
        let decoder = JSONDecoder()
        return try decoder.decode(APISessionSendMessageResult.self, from: responseData)
    }

    public func fetchGeminiSessionMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> [APISessionMessage] {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw MachinesAPIError.rpcCallFailed("Session ID is required")
        }

        let responseData = try await invokeSensitiveCommand(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            command: "gemini-list-messages",
            params: [
                "sessionId": .string(normalizedSessionID),
            ]
        )
        let raw = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        if raw?["success"] as? Bool == false {
            let normalizedError = (raw?["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MachinesAPIError.rpcCallFailed(
                (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "RPC call failed"
            )
        }
        let decoder = JSONDecoder()
        return try decoder.decode(CodexThreadMessagesEnvelope.self, from: responseData).messages
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

        let responseData = try await invokeSensitiveCommand(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            command: "gemini-send-message",
            params: params
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
}

private struct CodexThreadMessagesEnvelope: Decodable {
    let success: Bool
    let messages: [APISessionMessage]
}
