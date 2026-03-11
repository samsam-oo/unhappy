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

    public static func makeDeleteRequest(
        serverURL: URL,
        token: String,
        machineID: String
    ) throws -> URLRequest {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let machineURL = serverURL.appending(path: "v1/machines/\(normalizedMachineID)")
        return try makeRequest(
            url: machineURL,
            method: "DELETE",
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
        environmentVariables: [String: String]? = nil,
        model: String? = nil,
        reasoningEffort: APISessionReasoningEffort? = nil
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
            environmentVariables: environmentVariables,
            model: model?.trimmingCharacters(in: .whitespacesAndNewlines),
            reasoningEffort: reasoningEffort
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    public static func makeListModelsRequest(
        serverURL: URL,
        token: String,
        machineID: String,
        agent: APISessionSpawnAgent
    ) throws -> URLRequest {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let modelsURL = serverURL.appending(path: "v1/machines/\(normalizedMachineID)/models")
        guard var components = URLComponents(url: modelsURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "agent", value: agent.rawValue)]
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return try makeRequest(url: url, method: "GET", token: token)
    }

    public static func makeListProjectsRequest(
        serverURL: URL,
        token: String,
        machineID: String,
        explicitOnly: Bool = false
    ) throws -> URLRequest {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let projectsURL = serverURL.appending(path: "v1/machines/\(normalizedMachineID)/projects")
        guard var components = URLComponents(url: projectsURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        if explicitOnly {
            components.queryItems = [URLQueryItem(name: "explicitOnly", value: "true")]
        }
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return try makeRequest(url: url, method: "GET", token: token)
    }

    public static func makeProjectCatalogProjectsRequest(
        serverURL: URL,
        token: String,
        machineID: String
    ) throws -> URLRequest {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let projectsURL = serverURL.appending(path: "v1/machines/\(normalizedMachineID)/project-catalog/projects")
        return try makeRequest(url: projectsURL, method: "GET", token: token)
    }

    public static func makeOpenProjectRequest(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String
    ) throws -> URLRequest {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw MachinesAPIError.missingPath
        }
        let openProjectURL = serverURL.appending(path: "v1/machines/\(normalizedMachineID)/projects/open")
        var request = try makeRequest(url: openProjectURL, method: "POST", token: token)
        request.httpBody = try JSONEncoder().encode(["path": normalizedPath])
        return request
    }

    public static func makeProjectSessionsCatalogRequest(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        limit: Int = 100,
        cursor: String? = nil
    ) throws -> URLRequest {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw MachinesAPIError.missingPath
        }

        let catalogURL = serverURL.appending(path: "v1/machines/\(normalizedMachineID)/session-catalog/project-sessions")
        guard var components = URLComponents(url: catalogURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "path", value: normalizedPath),
            URLQueryItem(name: "limit", value: "\(min(max(limit, 1), 200))"),
        ]
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

    public static func makeRecentSessionCatalogRequest(
        serverURL: URL,
        token: String,
        limit: Int = 100,
        cursor: String? = nil
    ) throws -> URLRequest {
        let recentURL = serverURL.appending(path: "v1/session-catalog/recent")
        guard var components = URLComponents(url: recentURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(min(max(limit, 1), 200))"),
        ]
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

    public static func makeRemoveProjectRequest(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String
    ) throws -> URLRequest {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw MachinesAPIError.missingPath
        }
        let removeProjectURL = serverURL.appending(path: "v1/machines/\(normalizedMachineID)/projects/remove")
        var request = try makeRequest(url: removeProjectURL, method: "POST", token: token)
        request.httpBody = try JSONEncoder().encode(["path": normalizedPath])
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

    public static func makeGeminiSessionsRequest(
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

        let sessionsURL = serverURL.appending(path: "v1/machines/\(normalizedMachineID)/gemini/sessions")
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

    public static func decodeGeminiSessionsResponse(_ data: Data) throws -> [APIGeminiSessionSummary] {
        try decodeGeminiSessionsPageResponse(data).sessions
    }

    public static func decodeGeminiSessionsPageResponse(_ data: Data) throws -> APIGeminiSessionsPage {
        let decoder = JSONDecoder()
        let response = try decoder.decode(MachinesGeminiSessionsResponse.self, from: data)
        let nextCursor = response.nextCursor?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCursor = (nextCursor?.isEmpty == true) ? nil : nextCursor
        let hasNext = response.hasNext ?? (normalizedCursor != nil)
        return APIGeminiSessionsPage(
            sessions: response.sessions ?? [],
            nextCursor: normalizedCursor,
            hasNext: hasNext
        )
    }

    public static func decodeProjectSessionsPageResponse(_ data: Data) throws -> APIProjectSessionsPage {
        let decoder = JSONDecoder()
        let response = try decoder.decode(MachinesProjectSessionsResponse.self, from: data)
        let nextCursor = response.nextCursor?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCursor = (nextCursor?.isEmpty == true) ? nil : nextCursor
        let hasNext = response.hasNext ?? (normalizedCursor != nil)
        let normalizedError = response.error?.trimmingCharacters(in: .whitespacesAndNewlines)
        return APIProjectSessionsPage(
            sessions: response.sessions ?? [],
            nextCursor: normalizedCursor,
            hasNext: hasNext,
            error: normalizedError?.isEmpty == false ? normalizedError : nil
        )
    }

    public static func decodeRecentCatalogSessionsPageResponse(_ data: Data) throws -> APIRecentCatalogSessionsPage {
        let decoder = JSONDecoder()
        let response = try decoder.decode(MachinesRecentCatalogSessionsResponse.self, from: data)
        let nextCursor = response.nextCursor?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCursor = (nextCursor?.isEmpty == true) ? nil : nextCursor
        let hasNext = response.hasNext ?? (normalizedCursor != nil)
        return APIRecentCatalogSessionsPage(
            sessions: response.sessions ?? [],
            nextCursor: normalizedCursor,
            hasNext: hasNext
        )
    }

    public static func decodeAgentCapabilitiesResponse(_ data: Data) throws -> APIMachineAgentCapabilities {
        let decoder = JSONDecoder()
        let response = try decoder.decode(MachinesListModelsResponse.self, from: data)
        guard response.success else {
            let normalizedError = response.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MachinesAPIError.rpcCallFailed(
                (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "Failed to list models"
            )
        }

        func normalized(_ value: String?) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        let modelCapabilities: [APIMachineModelCapability] = (response.modelMetadata ?? []).compactMap { row in
            guard let id = normalized(row.id) ?? normalized(row.model) else {
                return nil
            }
            let supportedReasoningEfforts = deduplicatedValues(
                (row.supportedReasoningEfforts ?? [])
                    .compactMap { normalized($0.reasoningEffort) }
            )
            return APIMachineModelCapability(
                id: id,
                model: normalized(row.model),
                displayName: normalized(row.displayName),
                description: normalized(row.description),
                defaultReasoningEffort: normalized(row.defaultReasoningEffort),
                supportedReasoningEfforts: supportedReasoningEfforts,
                isDefault: row.isDefault,
                supportsPersonality: row.supportsPersonality,
                hidden: row.hidden,
                upgrade: normalized(row.upgrade)
            )
        }

        let rawModels = (response.models?.isEmpty == false)
            ? (response.models ?? [])
            : modelCapabilities.map(\.id)
        let rawReasoningEfforts = (response.reasoningEfforts ?? [])
            + modelCapabilities.flatMap(\.supportedReasoningEfforts)
        return APIMachineAgentCapabilities(
            models: deduplicatedValues(rawModels),
            reasoningEfforts: deduplicatedValues(rawReasoningEfforts),
            modelCapabilities: modelCapabilities
        )
    }

    public static func decodeProjectsResponse(_ data: Data) throws -> [APIMachineProjectSummary] {
        let decoder = JSONDecoder()
        let response = try decoder.decode(MachinesProjectsResponse.self, from: data)
        guard response.success else {
            let normalizedError = response.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MachinesAPIError.rpcCallFailed(
                (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "Failed to list projects"
            )
        }
        return response.projects ?? []
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
    case missingThreadID
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
        case .missingThreadID:
            return "Thread ID is required"
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

    public var reconnectingStatusText: String? {
        switch self {
        case .rpcTimedOut:
            return "Reconnecting to machine…"
        case .rpcCallFailed(let message):
            let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == "machine data-plane socket is not connected" ||
                normalized == "peer data-plane connection is not ready" ||
                normalized == "peer data-plane connection closed before the stream completed" ||
                normalized == "peer data-plane connection was superseded by a newer connection" {
                return "Reconnecting to machine…"
            }
            return nil
        default:
            return nil
        }
    }

    public static func reconnectingStatusText(from error: Error) -> String? {
        (error as? MachinesAPIError)?.reconnectingStatusText
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

private struct MachinesGeminiSessionsResponse: Decodable {
    let success: Bool
    let sessions: [APIGeminiSessionSummary]?
    let nextCursor: String?
    let hasNext: Bool?
}

private struct MachinesProjectSessionsResponse: Decodable {
    let success: Bool
    let sessions: [APIUpstreamSessionSummary]?
    let nextCursor: String?
    let hasNext: Bool?
    let error: String?
}

private struct MachinesRecentCatalogSessionsResponse: Decodable {
    let success: Bool
    let sessions: [APICatalogSessionSummary]?
    let nextCursor: String?
    let hasNext: Bool?
}

private struct MachinesListModelsResponse: Decodable {
    let success: Bool
    let models: [String]?
    let reasoningEfforts: [String]?
    let modelMetadata: [MachinesModelMetadata]?
    let error: String?
}

private struct MachinesProjectsResponse: Decodable {
    let success: Bool
    let projects: [APIMachineProjectSummary]?
    let error: String?
}

private struct MachinesModelReasoningEffort: Decodable {
    let reasoningEffort: String?
    let description: String?

    private enum CodingKeys: CodingKey {
        case reasoningEffort
        case legacyReasoningEffort
        case effort
        case description

        init?(stringValue: String) {
            switch stringValue {
            case "reasoningEffort":
                self = .reasoningEffort
            case "reasoning_effort":
                self = .legacyReasoningEffort
            case "effort":
                self = .effort
            case "description":
                self = .description
            default:
                return nil
            }
        }

        var stringValue: String {
            switch self {
            case .reasoningEffort:
                return "reasoningEffort"
            case .legacyReasoningEffort:
                return "reasoning_effort"
            case .effort:
                return "effort"
            case .description:
                return "description"
            }
        }

        init?(intValue: Int) { nil }
        var intValue: Int? { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reasoningEffort =
            (try? container.decodeIfPresent(String.self, forKey: .reasoningEffort))
            ?? (try? container.decodeIfPresent(String.self, forKey: .legacyReasoningEffort))
            ?? (try? container.decodeIfPresent(String.self, forKey: .effort))
        description = try? container.decodeIfPresent(String.self, forKey: .description)
    }
}

private struct MachinesModelMetadata: Decodable {
    let id: String?
    let model: String?
    let displayName: String?
    let description: String?
    let hidden: Bool?
    let isDefault: Bool?
    let supportsPersonality: Bool?
    let defaultReasoningEffort: String?
    let supportedReasoningEfforts: [MachinesModelReasoningEffort]?
    let upgrade: String?

    private enum CodingKeys: CodingKey {
        case id
        case model
        case displayName
        case description
        case hidden
        case isDefault
        case supportsPersonality
        case defaultReasoningEffort
        case legacyDefaultReasoningEffort
        case supportedReasoningEfforts
        case legacySupportedReasoningEfforts
        case upgrade

        init?(stringValue: String) {
            switch stringValue {
            case "id":
                self = .id
            case "model":
                self = .model
            case "displayName":
                self = .displayName
            case "description":
                self = .description
            case "hidden":
                self = .hidden
            case "isDefault":
                self = .isDefault
            case "supportsPersonality":
                self = .supportsPersonality
            case "defaultReasoningEffort":
                self = .defaultReasoningEffort
            case "default_reasoning_effort":
                self = .legacyDefaultReasoningEffort
            case "supportedReasoningEfforts":
                self = .supportedReasoningEfforts
            case "supported_reasoning_efforts":
                self = .legacySupportedReasoningEfforts
            case "upgrade":
                self = .upgrade
            default:
                return nil
            }
        }

        var stringValue: String {
            switch self {
            case .id:
                return "id"
            case .model:
                return "model"
            case .displayName:
                return "displayName"
            case .description:
                return "description"
            case .hidden:
                return "hidden"
            case .isDefault:
                return "isDefault"
            case .supportsPersonality:
                return "supportsPersonality"
            case .defaultReasoningEffort:
                return "defaultReasoningEffort"
            case .legacyDefaultReasoningEffort:
                return "default_reasoning_effort"
            case .supportedReasoningEfforts:
                return "supportedReasoningEfforts"
            case .legacySupportedReasoningEfforts:
                return "supported_reasoning_efforts"
            case .upgrade:
                return "upgrade"
            }
        }

        init?(intValue: Int) { nil }
        var intValue: Int? { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        model = try? container.decodeIfPresent(String.self, forKey: .model)
        displayName = try? container.decodeIfPresent(String.self, forKey: .displayName)
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        hidden = try? container.decodeIfPresent(Bool.self, forKey: .hidden)
        isDefault = try? container.decodeIfPresent(Bool.self, forKey: .isDefault)
        supportsPersonality = try? container.decodeIfPresent(Bool.self, forKey: .supportsPersonality)
        defaultReasoningEffort =
            (try? container.decodeIfPresent(String.self, forKey: .defaultReasoningEffort))
            ?? (try? container.decodeIfPresent(String.self, forKey: .legacyDefaultReasoningEffort))
        supportedReasoningEfforts =
            (try? container.decodeIfPresent([MachinesModelReasoningEffort].self, forKey: .supportedReasoningEfforts))
            ?? (try? container.decodeIfPresent([MachinesModelReasoningEffort].self, forKey: .legacySupportedReasoningEfforts))
        upgrade = try? container.decodeIfPresent(String.self, forKey: .upgrade)
    }
}

private struct MachineSpawnPayload: Encodable {
    let directory: String
    let agent: APISessionSpawnAgent?
    let codexResumeThreadId: String?
    let claudeResumeSessionId: String?
    let approvedNewDirectoryCreation: Bool?
    let token: String?
    let environmentVariables: [String: String]?
    let model: String?
    let reasoningEffort: APISessionReasoningEffort?
}

private struct MachineListDirectoryPayload: Encodable {
    let path: String
    let includeStats: Bool?
    let types: [String]?
    let sort: Bool?
    let maxEntries: Int?
}

private func deduplicatedValues(_ values: [String]) -> [String] {
    var deduplicated: [String] = []
    var seen = Set<String>()
    for raw in values {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { continue }
        if seen.insert(normalized).inserted {
            deduplicated.append(normalized)
        }
    }
    return deduplicated
}

public protocol MachinesFetching: Sendable {
    func fetchMachines(serverURL: URL, token: String) async throws -> [APIMachine]
}

public struct MachineSessionSpawnServiceRequest: Sendable, Equatable {
    public let serverURL: URL
    public let token: String
    public let machineID: String
    public let wrappedMachineDataEncryptionKey: String?
    public let directory: String
    public let agent: APISessionSpawnAgent?
    public let codexResumeThreadID: String?
    public let claudeResumeSessionID: String?
    public let approvedNewDirectoryCreation: Bool?
    public let sessionToken: String?
    public let environmentVariables: [String: String]?
    public let model: String?
    public let reasoningEffort: APISessionReasoningEffort?

    public init(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String? = nil,
        directory: String,
        agent: APISessionSpawnAgent?,
        codexResumeThreadID: String? = nil,
        claudeResumeSessionID: String? = nil,
        approvedNewDirectoryCreation: Bool? = nil,
        sessionToken: String? = nil,
        environmentVariables: [String: String]? = nil,
        model: String? = nil,
        reasoningEffort: APISessionReasoningEffort? = nil
    ) {
        self.serverURL = serverURL
        self.token = token
        self.machineID = machineID
        self.wrappedMachineDataEncryptionKey = wrappedMachineDataEncryptionKey
        self.directory = directory
        self.agent = agent
        self.codexResumeThreadID = codexResumeThreadID
        self.claudeResumeSessionID = claudeResumeSessionID
        self.approvedNewDirectoryCreation = approvedNewDirectoryCreation
        self.sessionToken = sessionToken
        self.environmentVariables = environmentVariables
        self.model = model
        self.reasoningEffort = reasoningEffort
    }
}

public protocol MachineSessionSpawning: Sendable {
    func spawnSession(_ request: MachineSessionSpawnServiceRequest) async throws -> APISessionSpawnResult
}

public protocol MachineDaemonStopping: Sendable {
    func stopDaemon(serverURL: URL, token: String, machineID: String) async throws -> APIMachineCommandResult
}

public protocol MachineDaemonUpdating: Sendable {
    func updateDaemon(serverURL: URL, token: String, machineID: String) async throws -> APIMachineCommandResult
}

public protocol MachineDeleting: Sendable {
    func deleteMachine(serverURL: URL, token: String, machineID: String) async throws -> APIMachineCommandResult
}

public protocol MachineDirectoryListing: Sendable {
    func listDirectory(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APIMachineListDirectoryResult
}

public protocol MachineFileReading: Sendable {
    func readFile(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APISessionReadFileResult
}

public protocol MachineBashRunning: Sendable {
    func runBash(
        serverURL: URL,
        token: String,
        machineID: String,
        command: String,
        cwd: String,
        wrappedMachineDataEncryptionKey: String?,
        timeoutMilliseconds: Int
    ) async throws -> APISessionBashResult
}

public protocol MachineCodexThreadsFetching: Sendable {
    func fetchCodexThreadsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APICodexThreadsPage

    func fetchCodexThreads(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?
    ) async throws -> [APICodexThreadSummary]
}

public protocol MachineCodexThreadArchiving: Sendable {
    func archiveCodexThread(
        serverURL: URL,
        token: String,
        machineID: String,
        threadID: String,
        transcriptPath: String?,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APIMachineCommandResult
}

public protocol MachineCodexThreadMessagesFetching: Sendable {
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
}

public protocol MachineCodexThreadMessaging: Sendable {
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
}

public protocol MachineClaudeSessionsFetching: Sendable {
    func fetchClaudeSessionsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APIClaudeSessionsPage

    func fetchClaudeSessions(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?
    ) async throws -> [APIClaudeSessionSummary]
}

public protocol MachineClaudeSessionMessagesFetching: Sendable {
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
}

public protocol MachineClaudeSessionMessaging: Sendable {
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
}

public protocol MachineGeminiSessionsFetching: Sendable {
    func fetchGeminiSessionsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APIGeminiSessionsPage

    func fetchGeminiSessions(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?
    ) async throws -> [APIGeminiSessionSummary]
}

public protocol MachineProjectSessionsFetching: Sendable {
    func fetchProjectSessionsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        projectPath: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APIProjectSessionsPage
}

public protocol MachineRecentSessionCatalogFetching: Sendable {
    func fetchRecentSessionCatalogPage(
        serverURL: URL,
        token: String,
        limit: Int,
        cursor: String?
    ) async throws -> APIRecentCatalogSessionsPage
}

public protocol MachineGeminiSessionMessagesFetching: Sendable {
    func fetchGeminiSessionMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage
}

public protocol MachineGeminiSessionMessaging: Sendable {
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

public protocol MachineModelsListing: Sendable {
    func fetchAgentCapabilities(
        serverURL: URL,
        token: String,
        machineID: String,
        agent: APISessionSpawnAgent
    ) async throws -> APIMachineAgentCapabilities
}

public protocol MachineProjectsFetching: Sendable {
    func fetchProjects(
        serverURL: URL,
        token: String,
        machineID: String,
        explicitOnly: Bool,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> [APIMachineProjectSummary]
}

public protocol MachineProjectOpening: Sendable {
    func openProject(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APIMachineCommandResult
}

public protocol MachineProjectRemoving: Sendable {
    func removeProject(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APIMachineCommandResult
}

public protocol MachineHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionMachineHTTPClient: MachineHTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, httpResponse)
    }
}

public struct APIMachineAgentCapabilities: Equatable, Sendable {
    public let models: [String]
    public let reasoningEfforts: [String]
    public let modelCapabilities: [APIMachineModelCapability]

    public init(
        models: [String],
        reasoningEfforts: [String],
        modelCapabilities: [APIMachineModelCapability] = []
    ) {
        self.models = models
        self.reasoningEfforts = reasoningEfforts
        self.modelCapabilities = modelCapabilities
    }
}

public struct APIMachineModelCapability: Equatable, Sendable {
    public let id: String
    public let model: String?
    public let displayName: String?
    public let description: String?
    public let defaultReasoningEffort: String?
    public let supportedReasoningEfforts: [String]
    public let isDefault: Bool?
    public let supportsPersonality: Bool?
    public let hidden: Bool?
    public let upgrade: String?

    public init(
        id: String,
        model: String?,
        displayName: String?,
        description: String?,
        defaultReasoningEffort: String?,
        supportedReasoningEfforts: [String],
        isDefault: Bool?,
        supportsPersonality: Bool?,
        hidden: Bool?,
        upgrade: String?
    ) {
        self.id = id
        self.model = model
        self.displayName = displayName
        self.description = description
        self.defaultReasoningEffort = defaultReasoningEffort
        self.supportedReasoningEfforts = supportedReasoningEfforts
        self.isDefault = isDefault
        self.supportsPersonality = supportsPersonality
        self.hidden = hidden
        self.upgrade = upgrade
    }
}

public actor URLSessionMachinesService:
    MachinesFetching,
    MachineSessionSpawning,
    MachineDaemonStopping,
    MachineDaemonUpdating,
    MachineDeleting,
    MachineDirectoryListing,
    MachineFileReading,
    MachineBashRunning,
    MachineCodexThreadsFetching,
    MachineCodexThreadArchiving,
    MachineCodexThreadMessagesFetching,
    MachineCodexThreadMessaging,
    MachineClaudeSessionsFetching,
    MachineClaudeSessionMessagesFetching,
    MachineClaudeSessionMessaging,
    MachineGeminiSessionsFetching,
    MachineProjectSessionsFetching,
    MachineRecentSessionCatalogFetching,
    MachineGeminiSessionMessagesFetching,
    MachineGeminiSessionMessaging,
    MachineModelsListing,
    MachineProjectsFetching,
    MachineProjectOpening,
    MachineProjectRemoving {
    struct MachinesCacheKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
    }

    struct MachinesCacheEntry: Sendable {
        let machines: [APIMachine]
        let cachedAt: TimeInterval
    }

    enum MachinesCachePolicy {
        static let ttl: TimeInterval = 5
    }

    struct ProjectsCacheKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let machineID: String
        let explicitOnly: Bool
    }

    struct ProjectsCacheEntry: Sendable {
        let projects: [APIMachineProjectSummary]
        let cachedAt: TimeInterval
    }

    struct MachineDataPlanePrewarmKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let machineID: String
        let wrappedMachineDataEncryptionKey: String
    }

    enum MachineDataPlanePrewarmConfig {
        static let throttleInterval: TimeInterval = 20
        static let recentActivityInterval: TimeInterval = 30
    }

    let httpClient: any MachineHTTPClient
    let rpcDirectoryService: any MachineRPCDirectoryListing
    let prewarmPolicy: any MachineDataPlanePrewarmPolicy
    var machinesCache: [MachinesCacheKey: MachinesCacheEntry] = [:]
    var inFlightMachineFetches: [MachinesCacheKey: Task<[APIMachine], Error>] = [:]
    var projectsCache: [ProjectsCacheKey: ProjectsCacheEntry] = [:]
    var inFlightProjectFetches: [ProjectsCacheKey: Task<[APIMachineProjectSummary], Error>] = [:]
    var lastMachineDataPlanePrewarmAt: [MachineDataPlanePrewarmKey: TimeInterval] = [:]

    public init(
        httpClient: any MachineHTTPClient = URLSessionMachineHTTPClient(),
        rpcDirectoryService: any MachineRPCDirectoryListing = SocketIOMachineRPCDirectoryService(),
        prewarmPolicy: any MachineDataPlanePrewarmPolicy = DefaultMachineDataPlanePrewarmPolicy.shared
    ) {
        self.httpClient = httpClient
        self.rpcDirectoryService = rpcDirectoryService
        self.prewarmPolicy = prewarmPolicy
    }
}
