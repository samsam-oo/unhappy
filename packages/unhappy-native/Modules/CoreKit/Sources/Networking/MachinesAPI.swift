import Foundation

public enum MachinesAPI {
    public static func makeListRequest(serverURL: URL, token: String) throws -> URLRequest {
        let machinesURL = serverURL.appending(path: "v1/machines")
        return try makeRequest(
            url: machinesURL,
            method: "GET",
            token: token
        )
    }

    public static func makeSpawnSessionRequest(
        serverURL: URL,
        token: String,
        machineID: String,
        directory: String,
        agent: APISessionSpawnAgent? = nil,
        codexResumeThreadID: String? = nil,
        claudeResumeSessionID: String? = nil,
        approvedNewDirectoryCreation: Bool? = nil,
        sessionToken: String? = nil,
        environmentVariables: [String: String]? = nil
    ) throws -> URLRequest {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let normalizedDirectory = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDirectory.isEmpty else {
            throw MachinesAPIError.missingDirectory
        }

        let spawnURL = serverURL.appending(path: "v1/machines/\(normalizedMachineID)/spawn")
        var request = try makeRequest(
            url: spawnURL,
            method: "POST",
            token: token
        )
        let payload = MachineSpawnPayload(
            directory: normalizedDirectory,
            agent: agent,
            codexResumeThreadId: codexResumeThreadID?.trimmingCharacters(in: .whitespacesAndNewlines),
            claudeResumeSessionId: claudeResumeSessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
            approvedNewDirectoryCreation: approvedNewDirectoryCreation,
            token: sessionToken?.trimmingCharacters(in: .whitespacesAndNewlines),
            environmentVariables: environmentVariables
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    public static func makeCodexThreadsRequest(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int = 20,
        cwd: String? = nil,
        cursor: String? = nil
    ) throws -> URLRequest {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }

        let threadsURL = serverURL.appending(path: "v1/machines/\(normalizedMachineID)/codex/threads")
        guard var components = URLComponents(url: threadsURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "limit", value: "\(limit)")]
        let normalizedCWD = cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCWD, !normalizedCWD.isEmpty {
            queryItems.append(URLQueryItem(name: "cwd", value: normalizedCWD))
        }
        let normalizedCursor = cursor?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCursor, !normalizedCursor.isEmpty {
            queryItems.append(URLQueryItem(name: "cursor", value: normalizedCursor))
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return try makeRequest(url: url, method: "GET", token: token)
    }

    public static func makeClaudeSessionsRequest(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int = 20,
        cwd: String? = nil,
        cursor: String? = nil
    ) throws -> URLRequest {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }

        let sessionsURL = serverURL.appending(path: "v1/machines/\(normalizedMachineID)/claude/sessions")
        guard var components = URLComponents(url: sessionsURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "limit", value: "\(limit)")]
        let normalizedCWD = cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCWD, !normalizedCWD.isEmpty {
            queryItems.append(URLQueryItem(name: "cwd", value: normalizedCWD))
        }
        let normalizedCursor = cursor?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCursor, !normalizedCursor.isEmpty {
            queryItems.append(URLQueryItem(name: "cursor", value: normalizedCursor))
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return try makeRequest(url: url, method: "GET", token: token)
    }

    public static func makeStopDaemonRequest(
        serverURL: URL,
        token: String,
        machineID: String
    ) throws -> URLRequest {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let stopURL = serverURL.appending(path: "v1/machines/\(normalizedMachineID)/daemon/stop")
        return try makeRequest(url: stopURL, method: "POST", token: token)
    }

    public static func makeUpdateDaemonRequest(
        serverURL: URL,
        token: String,
        machineID: String
    ) throws -> URLRequest {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let updateURL = serverURL.appending(path: "v1/machines/\(normalizedMachineID)/daemon/update")
        return try makeRequest(url: updateURL, method: "POST", token: token)
    }

    public static func makeListDirectoryRequest(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        includeStats: Bool? = nil,
        types: [String]? = nil,
        sort: Bool? = nil,
        maxEntries: Int? = nil
    ) throws -> URLRequest {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw MachinesAPIError.missingPath
        }

        let listDirectoryURL = serverURL.appending(path: "v1/machines/\(normalizedMachineID)/commands/list-directory")
        var request = try makeRequest(
            url: listDirectoryURL,
            method: "POST",
            token: token
        )
        let payload = MachineListDirectoryPayload(
            path: normalizedPath,
            includeStats: includeStats,
            types: types,
            sort: sort,
            maxEntries: maxEntries
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    public static func decodeListResponse(_ data: Data) throws -> [APIMachine] {
        let decoder = JSONDecoder()
        return try decoder.decode([APIMachine].self, from: data)
    }

    public static func decodeSpawnResponse(_ data: Data) throws -> APISessionSpawnResult {
        let decoder = JSONDecoder()
        return try decoder.decode(APISessionSpawnResult.self, from: data)
    }

    public static func decodeCommandResponse(_ data: Data) throws -> APIMachineCommandResult {
        let decoder = JSONDecoder()
        return try decoder.decode(APIMachineCommandResult.self, from: data)
    }

    public static func decodeListDirectoryResponse(_ data: Data) throws -> APIMachineListDirectoryResult {
        let decoder = JSONDecoder()
        return try decoder.decode(APIMachineListDirectoryResult.self, from: data)
    }

    public static func decodeCodexThreadsResponse(_ data: Data) throws -> [APICodexThreadSummary] {
        try decodeCodexThreadsPageResponse(data).threads
    }

    public static func decodeCodexThreadsPageResponse(_ data: Data) throws -> APICodexThreadsPage {
        let decoder = JSONDecoder()
        let response = try decoder.decode(MachinesCodexThreadsResponse.self, from: data)
        let nextCursor = response.nextCursor?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCursor = (nextCursor?.isEmpty == true) ? nil : nextCursor
        let hasNext = response.hasNext ?? (normalizedCursor != nil)
        return APICodexThreadsPage(
            threads: response.threads ?? [],
            nextCursor: normalizedCursor,
            hasNext: hasNext
        )
    }

    public static func decodeClaudeSessionsResponse(_ data: Data) throws -> [APIClaudeSessionSummary] {
        try decodeClaudeSessionsPageResponse(data).sessions
    }

    public static func decodeClaudeSessionsPageResponse(_ data: Data) throws -> APIClaudeSessionsPage {
        let decoder = JSONDecoder()
        let response = try decoder.decode(MachinesClaudeSessionsResponse.self, from: data)
        let nextCursor = response.nextCursor?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCursor = (nextCursor?.isEmpty == true) ? nil : nextCursor
        let hasNext = response.hasNext ?? (normalizedCursor != nil)
        return APIClaudeSessionsPage(
            sessions: response.sessions ?? [],
            nextCursor: normalizedCursor,
            hasNext: hasNext
        )
    }

    private static func makeRequest(url: URL, method: String, token: String) throws -> URLRequest {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw MachinesAPIError.missingToken
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(normalizedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
}

public enum MachinesAPIError: LocalizedError, Equatable {
    case missingToken
    case missingMachineID
    case missingDirectory
    case missingPath
    case missingCommand
    case machineNotFound(String)
    case rpcSocketConnectionFailed(String)
    case rpcTimedOut
    case rpcCallFailed(String)
    case invalidRPCPayload
    case endpointUnavailable(String)
    case invalidHTTPStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .missingMachineID:
            return "Machine ID is required"
        case .missingDirectory:
            return "Directory is required"
        case .missingPath:
            return "Path is required"
        case .missingCommand:
            return "Command is required"
        case .machineNotFound(let machineID):
            return "Machine not found: \(machineID)"
        case .rpcSocketConnectionFailed(let reason):
            return "Failed to connect daemon RPC socket: \(reason)"
        case .rpcTimedOut:
            return "Daemon RPC timed out. The backend may be missing machine socket command bridge support or WebSocket traffic may be blocked."
        case .rpcCallFailed(let message):
            return "Daemon RPC failed: \(message)"
        case .invalidRPCPayload:
            return "Daemon RPC returned invalid payload"
        case .endpointUnavailable(let endpoint):
            return "Server endpoint is unavailable: \(endpoint). Update backend API server to latest."
        case .invalidHTTPStatus(let code):
            return "Request failed with status \(code)"
        }
    }
}

public struct APIMachineDirectoryEntry: Decodable, Equatable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let type: String
    public let size: Int?
    public let modified: TimeInterval?

    public init(name: String, type: String, size: Int?, modified: TimeInterval?) {
        self.name = name
        self.type = type
        self.size = size
        self.modified = modified
    }
}

public struct APIMachineListDirectoryResult: Decodable, Equatable, Sendable {
    public let success: Bool
    public let entries: [APIMachineDirectoryEntry]?
    public let error: String?

    public init(success: Bool, entries: [APIMachineDirectoryEntry]?, error: String?) {
        self.success = success
        self.entries = entries
        self.error = error
    }
}

private struct MachinesCodexThreadsResponse: Decodable {
    let success: Bool
    let threads: [APICodexThreadSummary]?
    let nextCursor: String?
    let hasNext: Bool?
}

private struct MachinesClaudeSessionsResponse: Decodable {
    let success: Bool
    let sessions: [APIClaudeSessionSummary]?
    let nextCursor: String?
    let hasNext: Bool?
}

private struct MachineSpawnPayload: Encodable {
    let directory: String
    let agent: APISessionSpawnAgent?
    let codexResumeThreadId: String?
    let claudeResumeSessionId: String?
    let approvedNewDirectoryCreation: Bool?
    let token: String?
    let environmentVariables: [String: String]?
}

private struct MachineListDirectoryPayload: Encodable {
    let path: String
    let includeStats: Bool?
    let types: [String]?
    let sort: Bool?
    let maxEntries: Int?
}

public protocol MachinesFetching: Sendable {
    func fetchMachines(serverURL: URL, token: String) async throws -> [APIMachine]
}

public protocol MachineSessionSpawning: Sendable {
    func spawnSession(
        serverURL: URL,
        token: String,
        machineID: String,
        directory: String,
        agent: APISessionSpawnAgent?,
        codexResumeThreadID: String?,
        claudeResumeSessionID: String?,
        approvedNewDirectoryCreation: Bool?,
        sessionToken: String?,
        environmentVariables: [String: String]?
    ) async throws -> APISessionSpawnResult
}

public protocol MachineDaemonStopping: Sendable {
    func stopDaemon(serverURL: URL, token: String, machineID: String) async throws -> APIMachineCommandResult
}

public protocol MachineDaemonUpdating: Sendable {
    func updateDaemon(serverURL: URL, token: String, machineID: String) async throws -> APIMachineCommandResult
}

public protocol MachineDirectoryListing: Sendable {
    func listDirectory(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String
    ) async throws -> APIMachineListDirectoryResult
}

public protocol MachineCodexThreadsFetching: Sendable {
    func fetchCodexThreadsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APICodexThreadsPage

    func fetchCodexThreads(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?
    ) async throws -> [APICodexThreadSummary]
}

public protocol MachineClaudeSessionsFetching: Sendable {
    func fetchClaudeSessionsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APIClaudeSessionsPage

    func fetchClaudeSessions(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?
    ) async throws -> [APIClaudeSessionSummary]
}

public actor URLSessionMachinesService: MachinesFetching, MachineSessionSpawning, MachineDaemonStopping, MachineDaemonUpdating, MachineDirectoryListing, MachineCodexThreadsFetching, MachineClaudeSessionsFetching {
    private let rpcDirectoryService: any MachineRPCDirectoryListing

    public init(
        rpcDirectoryService: any MachineRPCDirectoryListing = SocketIOMachineRPCDirectoryService()
    ) {
        self.rpcDirectoryService = rpcDirectoryService
    }

    public func fetchMachines(serverURL: URL, token: String) async throws -> [APIMachine] {
        let request = try MachinesAPI.makeListRequest(serverURL: serverURL, token: token)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MachinesAPIError.invalidHTTPStatus(http.statusCode)
        }

        return try MachinesAPI.decodeListResponse(data)
    }

    public func spawnSession(
        serverURL: URL,
        token: String,
        machineID: String,
        directory: String,
        agent: APISessionSpawnAgent?,
        codexResumeThreadID: String?,
        claudeResumeSessionID: String?,
        approvedNewDirectoryCreation: Bool?,
        sessionToken: String?,
        environmentVariables: [String: String]?
    ) async throws -> APISessionSpawnResult {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let normalizedDirectory = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDirectory.isEmpty else {
            throw MachinesAPIError.missingDirectory
        }

        var params: [String: Any] = [
            "directory": normalizedDirectory,
            "machineId": normalizedMachineID,
        ]
        if let agent {
            params["agent"] = agent.rawValue
        }
        let normalizedCodexResumeThreadID = codexResumeThreadID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCodexResumeThreadID, !normalizedCodexResumeThreadID.isEmpty {
            params["codexResumeThreadId"] = normalizedCodexResumeThreadID
        }
        let normalizedClaudeResumeSessionID = claudeResumeSessionID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedClaudeResumeSessionID, !normalizedClaudeResumeSessionID.isEmpty {
            params["claudeResumeSessionId"] = normalizedClaudeResumeSessionID
        }
        if let approvedNewDirectoryCreation {
            params["approvedNewDirectoryCreation"] = approvedNewDirectoryCreation
        }
        let normalizedSessionToken = sessionToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedSessionToken, !normalizedSessionToken.isEmpty {
            params["token"] = normalizedSessionToken
        }
        if let environmentVariables {
            params["environmentVariables"] = environmentVariables
        }

        let data = try await rpcDirectoryService.invokeCommand(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            command: "spawn-unhappy-session",
            params: params
        )

        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MachinesAPIError.invalidRPCPayload
        }

        if let type = payload["type"] as? String {
            if type == "requestToApproveDirectoryCreation" {
                return APISessionSpawnResult(
                    success: false,
                    sessionID: nil,
                    requiresUserApproval: true,
                    actionRequired: "CREATE_DIRECTORY",
                    directory: payload["directory"] as? String,
                    error: nil
                )
            }
            if type == "success", let sessionID = payload["sessionId"] as? String {
                return APISessionSpawnResult(
                    success: true,
                    sessionID: sessionID,
                    requiresUserApproval: nil,
                    actionRequired: nil,
                    directory: nil,
                    error: nil
                )
            }
        }

        if payload["success"] as? Bool == false {
            return APISessionSpawnResult(
                success: false,
                sessionID: nil,
                requiresUserApproval: nil,
                actionRequired: nil,
                directory: nil,
                error: payload["error"] as? String
            )
        }

        return APISessionSpawnResult(
            success: false,
            sessionID: nil,
            requiresUserApproval: nil,
            actionRequired: nil,
            directory: nil,
            error: (payload["error"] as? String) ?? (payload["errorMessage"] as? String) ?? "Failed to spawn session"
        )
    }

    public func stopDaemon(serverURL: URL, token: String, machineID: String) async throws -> APIMachineCommandResult {
        let data = try await rpcDirectoryService.invokeCommand(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            command: "stop-daemon",
            params: [:]
        )
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MachinesAPIError.invalidRPCPayload
        }

        let success = payload["success"] as? Bool ?? false
        let normalizedError = (payload["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if !success {
            throw MachinesAPIError.rpcCallFailed(
                (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "Failed to stop daemon"
            )
        }
        let normalizedMessage = (payload["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return APIMachineCommandResult(
            success: true,
            message: (normalizedMessage?.isEmpty == false ? normalizedMessage : nil) ?? "Daemon stop request acknowledged",
            error: nil
        )
    }

    public func updateDaemon(serverURL: URL, token: String, machineID: String) async throws -> APIMachineCommandResult {
        let data = try await rpcDirectoryService.invokeCommand(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            command: "update-daemon",
            params: [:]
        )
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MachinesAPIError.invalidRPCPayload
        }

        let success = payload["success"] as? Bool ?? false
        let normalizedError = (payload["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if !success {
            throw MachinesAPIError.rpcCallFailed(
                (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "Failed to update daemon"
            )
        }
        let normalizedMessage = (payload["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return APIMachineCommandResult(
            success: true,
            message: (normalizedMessage?.isEmpty == false ? normalizedMessage : nil) ?? "Daemon update requested",
            error: nil
        )
    }

    public func listDirectory(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String
    ) async throws -> APIMachineListDirectoryResult {
        return try await rpcDirectoryService.listDirectory(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            path: path,
            machineDataEncryptionKey: nil
        )
    }

    public func fetchCodexThreads(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?
    ) async throws -> [APICodexThreadSummary] {
        let boundedLimit = min(max(limit, 1), 100)
        var cursor: String?
        var seenCursors: Set<String> = []
        var seenIDs: Set<String> = []
        var merged: [APICodexThreadSummary] = []

        for _ in 0..<50 {
            let page = try await fetchCodexThreadsPage(
                serverURL: serverURL,
                token: token,
                machineID: machineID,
                limit: boundedLimit,
                cwd: cwd,
                cursor: cursor
            )
            for row in page.threads where seenIDs.insert(row.id).inserted {
                merged.append(row)
            }

            guard page.hasNext, let nextCursor = page.nextCursor else {
                break
            }
            guard seenCursors.insert(nextCursor).inserted else {
                break
            }
            cursor = nextCursor
        }

        return merged
    }

    public func fetchCodexThreadsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APICodexThreadsPage {
        let boundedLimit = min(max(limit, 1), 100)
        return try await rpcDirectoryService.fetchCodexThreadsPage(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            limit: boundedLimit,
            cwd: cwd,
            cursor: cursor
        )
    }

    public func fetchClaudeSessions(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?
    ) async throws -> [APIClaudeSessionSummary] {
        let boundedLimit = min(max(limit, 1), 100)
        var cursor: String?
        var seenCursors: Set<String> = []
        var seenIDs: Set<String> = []
        var merged: [APIClaudeSessionSummary] = []

        for _ in 0..<50 {
            let page = try await fetchClaudeSessionsPage(
                serverURL: serverURL,
                token: token,
                machineID: machineID,
                limit: boundedLimit,
                cwd: cwd,
                cursor: cursor
            )
            for row in page.sessions where seenIDs.insert(row.id).inserted {
                merged.append(row)
            }

            guard page.hasNext, let nextCursor = page.nextCursor else {
                break
            }
            guard seenCursors.insert(nextCursor).inserted else {
                break
            }
            cursor = nextCursor
        }

        return merged
    }

    public func fetchClaudeSessionsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APIClaudeSessionsPage {
        let boundedLimit = min(max(limit, 1), 100)
        return try await rpcDirectoryService.fetchClaudeSessionsPage(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            limit: boundedLimit,
            cwd: cwd,
            cursor: cursor
        )
    }
}
