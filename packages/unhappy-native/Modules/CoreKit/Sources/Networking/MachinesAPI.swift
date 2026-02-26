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
    func fetchCodexThreads(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?
    ) async throws -> [APICodexThreadSummary]
}

public protocol MachineClaudeSessionsFetching: Sendable {
    func fetchClaudeSessions(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?
    ) async throws -> [APIClaudeSessionSummary]
}

public actor URLSessionMachinesService: MachinesFetching, MachineSessionSpawning, MachineDaemonStopping, MachineDaemonUpdating, MachineDirectoryListing, MachineCodexThreadsFetching, MachineClaudeSessionsFetching {
    public init() {}

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
        let request = try MachinesAPI.makeSpawnSessionRequest(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            directory: directory,
            agent: agent,
            codexResumeThreadID: codexResumeThreadID,
            claudeResumeSessionID: claudeResumeSessionID,
            approvedNewDirectoryCreation: approvedNewDirectoryCreation,
            sessionToken: sessionToken,
            environmentVariables: environmentVariables
        )
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 409 {
            return try MachinesAPI.decodeSpawnResponse(data)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MachinesAPIError.invalidHTTPStatus(http.statusCode)
        }

        return try MachinesAPI.decodeSpawnResponse(data)
    }

    public func stopDaemon(serverURL: URL, token: String, machineID: String) async throws -> APIMachineCommandResult {
        let request = try MachinesAPI.makeStopDaemonRequest(
            serverURL: serverURL,
            token: token,
            machineID: machineID
        )
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MachinesAPIError.invalidHTTPStatus(http.statusCode)
        }

        return try MachinesAPI.decodeCommandResponse(data)
    }

    public func updateDaemon(serverURL: URL, token: String, machineID: String) async throws -> APIMachineCommandResult {
        let request = try MachinesAPI.makeUpdateDaemonRequest(
            serverURL: serverURL,
            token: token,
            machineID: machineID
        )
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MachinesAPIError.invalidHTTPStatus(http.statusCode)
        }

        return try MachinesAPI.decodeCommandResponse(data)
    }

    public func listDirectory(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String
    ) async throws -> APIMachineListDirectoryResult {
        let request = try MachinesAPI.makeListDirectoryRequest(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            path: path,
            includeStats: true,
            types: ["file", "directory"],
            sort: true,
            maxEntries: 300
        )
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MachinesAPIError.invalidHTTPStatus(http.statusCode)
        }

        return try MachinesAPI.decodeListDirectoryResponse(data)
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
            let request = try MachinesAPI.makeCodexThreadsRequest(
                serverURL: serverURL,
                token: token,
                machineID: machineID,
                limit: boundedLimit,
                cwd: cwd,
                cursor: cursor
            )
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard (200..<300).contains(http.statusCode) else {
                throw MachinesAPIError.invalidHTTPStatus(http.statusCode)
            }

            let page = try MachinesAPI.decodeCodexThreadsPageResponse(data)
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
            let request = try MachinesAPI.makeClaudeSessionsRequest(
                serverURL: serverURL,
                token: token,
                machineID: machineID,
                limit: boundedLimit,
                cwd: cwd,
                cursor: cursor
            )
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard (200..<300).contains(http.statusCode) else {
                throw MachinesAPIError.invalidHTTPStatus(http.statusCode)
            }

            let page = try MachinesAPI.decodeClaudeSessionsPageResponse(data)
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
}
