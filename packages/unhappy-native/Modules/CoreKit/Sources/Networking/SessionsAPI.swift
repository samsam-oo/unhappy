import Foundation

public enum SessionsAPI {
    public static func makePagedListRequest(
        serverURL: URL,
        token: String,
        cursor: String? = nil,
        limit: Int = 50
    ) throws -> URLRequest {
        let boundedLimit = min(max(limit, 1), 200)
        let sessionsURL = serverURL.appending(path: "v2/sessions")
        guard var components = URLComponents(url: sessionsURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }

        var queryItems = [URLQueryItem(name: "limit", value: "\(boundedLimit)")]
        if let cursor, !cursor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components.queryItems = queryItems

        guard let requestURL = components.url else {
            throw URLError(.badURL)
        }

        return try makeRequest(
            url: requestURL,
            method: "GET",
            token: token
        )
    }

    public static func makeListRequest(serverURL: URL, token: String) throws -> URLRequest {
        let sessionsURL = serverURL.appending(path: "v1/sessions")
        return try makeRequest(
            url: sessionsURL,
            method: "GET",
            token: token
        )
    }

    public static func makeMessagesRequest(serverURL: URL, token: String, sessionID: String) throws -> URLRequest {
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionsAPIError.missingSessionID
        }

        let messagesURL = serverURL.appending(path: "v1/sessions/\(normalizedSessionID)/messages")
        return try makeRequest(
            url: messagesURL,
            method: "GET",
            token: token
        )
    }

    public static func makeDeleteRequest(serverURL: URL, token: String, sessionID: String) throws -> URLRequest {
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionsAPIError.missingSessionID
        }

        let deleteURL = serverURL.appending(path: "v1/sessions/\(normalizedSessionID)")
        return try makeRequest(
            url: deleteURL,
            method: "DELETE",
            token: token
        )
    }

    public static func makeSetTitleRequest(
        serverURL: URL,
        token: String,
        sessionID: String,
        title: String?
    ) throws -> URLRequest {
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionsAPIError.missingSessionID
        }

        let titleURL = serverURL.appending(path: "v1/sessions/\(normalizedSessionID)/title")
        var request = try makeRequest(
            url: titleURL,
            method: "PATCH",
            token: token
        )

        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = SessionTitlePayload(title: normalizedTitle?.isEmpty == true ? nil : normalizedTitle)
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    public static func makeSetCodexTitleRequest(
        serverURL: URL,
        token: String,
        sessionID: String,
        name: String
    ) throws -> URLRequest {
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionsAPIError.missingSessionID
        }

        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw SessionsAPIError.missingSessionTitle
        }

        let titleURL = serverURL.appending(path: "v1/sessions/\(normalizedSessionID)/codex/title")
        var request = try makeRequest(
            url: titleURL,
            method: "PATCH",
            token: token
        )

        let payload = SessionCodexTitlePayload(name: normalizedName)
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    public static func makeCodexThreadsRequest(
        serverURL: URL,
        token: String,
        sessionID: String,
        limit: Int = 20,
        cwd: String? = nil,
        cursor: String? = nil
    ) throws -> URLRequest {
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionsAPIError.missingSessionID
        }

        let boundedLimit = min(max(limit, 1), 100)
        let threadsURL = serverURL.appending(path: "v1/sessions/\(normalizedSessionID)/codex/threads")
        guard var components = URLComponents(url: threadsURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        var queryItems = [
            URLQueryItem(name: "limit", value: "\(boundedLimit)")
        ]
        let normalizedCWD = cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCWD, !normalizedCWD.isEmpty {
            queryItems.append(URLQueryItem(name: "cwd", value: normalizedCWD))
        }
        let normalizedCursor = cursor?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCursor, !normalizedCursor.isEmpty {
            queryItems.append(URLQueryItem(name: "cursor", value: normalizedCursor))
        }
        components.queryItems = queryItems
        guard let requestURL = components.url else {
            throw URLError(.badURL)
        }
        return try makeRequest(
            url: requestURL,
            method: "GET",
            token: token
        )
    }

    public static func makeClaudeSessionsRequest(
        serverURL: URL,
        token: String,
        sessionID: String,
        limit: Int = 20,
        cwd: String? = nil,
        cursor: String? = nil
    ) throws -> URLRequest {
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionsAPIError.missingSessionID
        }

        let boundedLimit = min(max(limit, 1), 100)
        let sessionsURL = serverURL.appending(path: "v1/sessions/\(normalizedSessionID)/claude/sessions")
        guard var components = URLComponents(url: sessionsURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        var queryItems = [
            URLQueryItem(name: "limit", value: "\(boundedLimit)")
        ]
        let normalizedCWD = cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCWD, !normalizedCWD.isEmpty {
            queryItems.append(URLQueryItem(name: "cwd", value: normalizedCWD))
        }
        let normalizedCursor = cursor?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCursor, !normalizedCursor.isEmpty {
            queryItems.append(URLQueryItem(name: "cursor", value: normalizedCursor))
        }
        components.queryItems = queryItems
        guard let requestURL = components.url else {
            throw URLError(.badURL)
        }
        return try makeRequest(
            url: requestURL,
            method: "GET",
            token: token
        )
    }

    public static func makeSpawnSessionRequest(
        serverURL: URL,
        token: String,
        sessionID: String,
        directory: String,
        agent: APISessionSpawnAgent? = nil,
        codexResumeThreadID: String? = nil,
        claudeResumeSessionID: String? = nil,
        approvedNewDirectoryCreation: Bool? = nil
    ) throws -> URLRequest {
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionsAPIError.missingSessionID
        }
        let normalizedDirectory = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDirectory.isEmpty else {
            throw SessionsAPIError.missingDirectory
        }
        let normalizedCodexResumeThreadID = codexResumeThreadID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedClaudeResumeSessionID = claudeResumeSessionID?.trimmingCharacters(in: .whitespacesAndNewlines)

        let spawnURL = serverURL.appending(path: "v1/sessions/\(normalizedSessionID)/spawn")
        var request = try makeRequest(
            url: spawnURL,
            method: "POST",
            token: token
        )
        let payload = SessionSpawnPayload(
            directory: normalizedDirectory,
            agent: agent,
            codexResumeThreadId: normalizedCodexResumeThreadID?.isEmpty == true ? nil : normalizedCodexResumeThreadID,
            claudeResumeSessionId: normalizedClaudeResumeSessionID?.isEmpty == true ? nil : normalizedClaudeResumeSessionID,
            approvedNewDirectoryCreation: approvedNewDirectoryCreation
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    public static func makeSessionAbortRequest(
        serverURL: URL,
        token: String,
        sessionID: String,
        reason: String? = nil
    ) throws -> URLRequest {
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionsAPIError.missingSessionID
        }

        let abortURL = serverURL.appending(path: "v1/sessions/\(normalizedSessionID)/commands/abort")
        var request = try makeRequest(
            url: abortURL,
            method: "POST",
            token: token
        )
        let normalizedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedReason, !normalizedReason.isEmpty {
            request.httpBody = try JSONEncoder().encode(SessionAbortPayload(reason: normalizedReason))
        }
        return request
    }

    public static func makeSessionPermissionRequest(
        serverURL: URL,
        token: String,
        sessionID: String,
        permissionRequestID: String,
        approved: Bool,
        mode: APISessionPermissionMode? = nil,
        allowTools: [String]? = nil,
        decision: APISessionPermissionDecision? = nil
    ) throws -> URLRequest {
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionsAPIError.missingSessionID
        }
        let normalizedPermissionRequestID = permissionRequestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPermissionRequestID.isEmpty else {
            throw SessionsAPIError.missingPermissionRequestID
        }

        let permissionURL = serverURL.appending(path: "v1/sessions/\(normalizedSessionID)/commands/permission")
        var request = try makeRequest(
            url: permissionURL,
            method: "POST",
            token: token
        )
        let normalizedAllowTools = allowTools?.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let payload = SessionPermissionPayload(
            id: normalizedPermissionRequestID,
            approved: approved,
            mode: mode,
            allowTools: normalizedAllowTools?.isEmpty == false ? normalizedAllowTools : nil,
            decision: decision
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    public static func makeSessionSwitchRequest(
        serverURL: URL,
        token: String,
        sessionID: String,
        to: APISessionSwitchTarget
    ) throws -> URLRequest {
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionsAPIError.missingSessionID
        }

        let switchURL = serverURL.appending(path: "v1/sessions/\(normalizedSessionID)/commands/switch")
        var request = try makeRequest(
            url: switchURL,
            method: "POST",
            token: token
        )
        request.httpBody = try JSONEncoder().encode(SessionSwitchPayload(to: to))
        return request
    }

    public static func makeSessionSendMessageRequest(
        serverURL: URL,
        token: String,
        sessionID: String,
        text: String,
        steerMode: APISessionSteerMode? = nil,
        permissionMode: APISessionMessagePermissionMode? = nil
    ) throws -> URLRequest {
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionsAPIError.missingSessionID
        }
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw SessionsAPIError.missingMessageText
        }

        let messageURL = serverURL.appending(path: "v1/sessions/\(normalizedSessionID)/commands/message")
        var request = try makeRequest(
            url: messageURL,
            method: "POST",
            token: token
        )
        request.httpBody = try JSONEncoder().encode(
            SessionMessagePayload(
                text: normalizedText,
                steerMode: steerMode,
                permissionMode: permissionMode
            )
        )
        return request
    }

    public static func makeSessionBashRequest(
        serverURL: URL,
        token: String,
        sessionID: String,
        command: String,
        cwd: String? = nil,
        timeout: Int? = nil
    ) throws -> URLRequest {
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionsAPIError.missingSessionID
        }
        let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCommand.isEmpty else {
            throw SessionsAPIError.missingCommand
        }

        let bashURL = serverURL.appending(path: "v1/sessions/\(normalizedSessionID)/commands/bash")
        var request = try makeRequest(
            url: bashURL,
            method: "POST",
            token: token
        )
        let payload = SessionBashPayload(
            command: normalizedCommand,
            cwd: cwd?.trimmingCharacters(in: .whitespacesAndNewlines),
            timeout: timeout
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    public static func makeSessionRipgrepRequest(
        serverURL: URL,
        token: String,
        sessionID: String,
        args: [String],
        cwd: String? = nil
    ) throws -> URLRequest {
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionsAPIError.missingSessionID
        }
        let normalizedArgs = args.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard !normalizedArgs.isEmpty else {
            throw SessionsAPIError.missingCommand
        }

        let ripgrepURL = serverURL.appending(path: "v1/sessions/\(normalizedSessionID)/commands/ripgrep")
        var request = try makeRequest(
            url: ripgrepURL,
            method: "POST",
            token: token
        )
        let payload = SessionRipgrepPayload(
            args: normalizedArgs,
            cwd: cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    public static func makeSessionDifftasticRequest(
        serverURL: URL,
        token: String,
        sessionID: String,
        args: [String],
        cwd: String? = nil
    ) throws -> URLRequest {
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionsAPIError.missingSessionID
        }
        let normalizedArgs = args.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard !normalizedArgs.isEmpty else {
            throw SessionsAPIError.missingCommand
        }

        let difftasticURL = serverURL.appending(path: "v1/sessions/\(normalizedSessionID)/commands/difftastic")
        var request = try makeRequest(
            url: difftasticURL,
            method: "POST",
            token: token
        )
        let payload = SessionDifftasticPayload(
            args: normalizedArgs,
            cwd: cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    public static func makeSessionReadFileRequest(
        serverURL: URL,
        token: String,
        sessionID: String,
        path: String
    ) throws -> URLRequest {
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionsAPIError.missingSessionID
        }
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw SessionsAPIError.missingPath
        }

        let readFileURL = serverURL.appending(path: "v1/sessions/\(normalizedSessionID)/commands/read-file")
        var request = try makeRequest(
            url: readFileURL,
            method: "POST",
            token: token
        )
        let payload = SessionReadFilePayload(path: normalizedPath)
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    public static func makeSessionWriteFileRequest(
        serverURL: URL,
        token: String,
        sessionID: String,
        path: String,
        content: String,
        expectedHash: String? = nil
    ) throws -> URLRequest {
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionsAPIError.missingSessionID
        }
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw SessionsAPIError.missingPath
        }
        guard !content.isEmpty else {
            throw SessionsAPIError.missingFileContent
        }

        let writeFileURL = serverURL.appending(path: "v1/sessions/\(normalizedSessionID)/commands/write-file")
        var request = try makeRequest(
            url: writeFileURL,
            method: "POST",
            token: token
        )
        let payload = SessionWriteFilePayload(
            path: normalizedPath,
            content: content,
            expectedHash: expectedHash?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    public static func makeSessionListDirectoryRequest(
        serverURL: URL,
        token: String,
        sessionID: String,
        path: String,
        includeStats: Bool? = nil,
        types: [String]? = nil,
        sort: Bool? = nil,
        maxEntries: Int? = nil
    ) throws -> URLRequest {
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionsAPIError.missingSessionID
        }
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw SessionsAPIError.missingPath
        }

        let listDirectoryURL = serverURL.appending(path: "v1/sessions/\(normalizedSessionID)/commands/list-directory")
        var request = try makeRequest(
            url: listDirectoryURL,
            method: "POST",
            token: token
        )
        let payload = SessionListDirectoryPayload(
            path: normalizedPath,
            includeStats: includeStats,
            types: types,
            sort: sort,
            maxEntries: maxEntries
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    public static func makeSessionKillRequest(
        serverURL: URL,
        token: String,
        sessionID: String
    ) throws -> URLRequest {
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionsAPIError.missingSessionID
        }

        let killURL = serverURL.appending(path: "v1/sessions/\(normalizedSessionID)/kill")
        return try makeRequest(
            url: killURL,
            method: "POST",
            token: token
        )
    }

    public static func decodeListResponse(_ data: Data) throws -> [APISession] {
        let decoder = JSONDecoder()
        let response = try decoder.decode(SessionsListResponse.self, from: data)
        return response.sessions
    }

    public static func decodePagedListResponse(_ data: Data) throws -> APISessionsPage {
        let decoder = JSONDecoder()
        let response = try decoder.decode(SessionsPagedListResponse.self, from: data)
        return APISessionsPage(
            sessions: response.sessions,
            nextCursor: response.nextCursor,
            hasNext: response.hasNext
        )
    }

    public static func decodeMessagesResponse(_ data: Data) throws -> [APISessionMessage] {
        let decoder = JSONDecoder()
        if let response = try? decoder.decode(SessionsMessagesResponse.self, from: data) {
            if let messages = response.messages {
                return messages
            }
            if let items = response.items {
                return items
            }
            if let rows = response.rows {
                return rows
            }
            if let dataRows = response.data {
                return dataRows
            }
        }

        if let array = try? decoder.decode([APISessionMessage].self, from: data) {
            return array
        }

        let strictResponse = try decoder.decode(SessionsMessagesResponse.self, from: data)
        return strictResponse.messages ?? []
    }

    public static func decodeCodexThreadsResponse(_ data: Data) throws -> [APICodexThreadSummary] {
        try decodeCodexThreadsPageResponse(data).threads
    }

    public static func decodeCodexThreadsPageResponse(_ data: Data) throws -> APICodexThreadsPage {
        let decoder = JSONDecoder()
        let response = try decoder.decode(SessionsCodexThreadsResponse.self, from: data)
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
        let response = try decoder.decode(SessionsClaudeListResponse.self, from: data)
        let nextCursor = response.nextCursor?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCursor = (nextCursor?.isEmpty == true) ? nil : nextCursor
        let hasNext = response.hasNext ?? (normalizedCursor != nil)
        return APIClaudeSessionsPage(
            sessions: response.sessions ?? [],
            nextCursor: normalizedCursor,
            hasNext: hasNext
        )
    }

    public static func decodeSpawnSessionResponse(_ data: Data) throws -> APISessionSpawnResult {
        let decoder = JSONDecoder()
        return try decoder.decode(APISessionSpawnResult.self, from: data)
    }

    public static func decodeSessionCommandResponse(_ data: Data) throws -> APISessionCommandResult {
        let decoder = JSONDecoder()
        return try decoder.decode(APISessionCommandResult.self, from: data)
    }

    public static func decodeSessionSwitchResponse(_ data: Data) throws -> APISessionSwitchResult {
        let decoder = JSONDecoder()
        return try decoder.decode(APISessionSwitchResult.self, from: data)
    }

    public static func decodeSessionSendMessageResponse(_ data: Data) throws -> APISessionSendMessageResult {
        let decoder = JSONDecoder()
        return try decoder.decode(APISessionSendMessageResult.self, from: data)
    }

    public static func decodeSessionBashResponse(_ data: Data) throws -> APISessionBashResult {
        let decoder = JSONDecoder()
        return try decoder.decode(APISessionBashResult.self, from: data)
    }

    public static func decodeSessionRipgrepResponse(_ data: Data) throws -> APISessionBashResult {
        let decoder = JSONDecoder()
        return try decoder.decode(APISessionBashResult.self, from: data)
    }

    public static func decodeSessionDifftasticResponse(_ data: Data) throws -> APISessionBashResult {
        let decoder = JSONDecoder()
        return try decoder.decode(APISessionBashResult.self, from: data)
    }

    public static func decodeSessionReadFileResponse(_ data: Data) throws -> APISessionReadFileResult {
        let decoder = JSONDecoder()
        return try decoder.decode(APISessionReadFileResult.self, from: data)
    }

    public static func decodeSessionWriteFileResponse(_ data: Data) throws -> APISessionWriteFileResult {
        let decoder = JSONDecoder()
        return try decoder.decode(APISessionWriteFileResult.self, from: data)
    }

    public static func decodeSessionListDirectoryResponse(_ data: Data) throws -> APISessionListDirectoryResult {
        let decoder = JSONDecoder()
        return try decoder.decode(APISessionListDirectoryResult.self, from: data)
    }

    public static func decodeSessionKillResponse(_ data: Data) throws -> APISessionKillResult {
        let decoder = JSONDecoder()
        return try decoder.decode(APISessionKillResult.self, from: data)
    }

    private static func makeRequest(url: URL, method: String, token: String) throws -> URLRequest {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw SessionsAPIError.missingToken
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(normalizedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
}

public enum SessionsAPIError: LocalizedError, Equatable {
    case missingToken
    case missingSessionID
    case missingPermissionRequestID
    case missingDirectory
    case missingPath
    case missingMessageText
    case missingFileContent
    case missingCommand
    case missingSessionTitle
    case invalidHTTPStatus(Int)
    case rpcSocketConnectionFailed(String)
    case rpcTimedOut
    case rpcCallFailed(String)
    case invalidRPCPayload

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .missingSessionID:
            return "Session ID is required"
        case .missingPermissionRequestID:
            return "Permission request ID is required"
        case .missingDirectory:
            return "Directory is required"
        case .missingPath:
            return "Path is required"
        case .missingMessageText:
            return "Message text is required"
        case .missingFileContent:
            return "File content is required"
        case .missingCommand:
            return "Command is required"
        case .missingSessionTitle:
            return "Session title is required"
        case .invalidHTTPStatus(let code):
            return "Request failed with status \(code)"
        case .rpcSocketConnectionFailed(let reason):
            return "Failed to connect session RPC socket: \(reason)"
        case .rpcTimedOut:
            return "Session RPC request timed out"
        case .rpcCallFailed(let reason):
            return reason
        case .invalidRPCPayload:
            return "Received invalid session RPC payload"
        }
    }
}

private struct SessionsListResponse: Decodable {
    let sessions: [APISession]
}

private struct SessionsMessagesResponse: Decodable {
    let messages: [APISessionMessage]?
    let items: [APISessionMessage]?
    let rows: [APISessionMessage]?
    let data: [APISessionMessage]?
}

private struct SessionsPagedListResponse: Decodable {
    let sessions: [APISession]
    let nextCursor: String?
    let hasNext: Bool
}

private struct SessionTitlePayload: Encodable {
    let title: String?
}

private struct SessionCodexTitlePayload: Encodable {
    let name: String
}

private struct SessionSpawnPayload: Encodable {
    let directory: String
    let agent: APISessionSpawnAgent?
    let codexResumeThreadId: String?
    let claudeResumeSessionId: String?
    let approvedNewDirectoryCreation: Bool?
}

private struct SessionAbortPayload: Encodable {
    let reason: String
}

private struct SessionPermissionPayload: Encodable {
    let id: String
    let approved: Bool
    let mode: APISessionPermissionMode?
    let allowTools: [String]?
    let decision: APISessionPermissionDecision?
}

private struct SessionSwitchPayload: Encodable {
    let to: APISessionSwitchTarget
}

private struct SessionMessagePayload: Encodable {
    let text: String
    let steerMode: APISessionSteerMode?
    let permissionMode: APISessionMessagePermissionMode?
}

private struct SessionBashPayload: Encodable {
    let command: String
    let cwd: String?
    let timeout: Int?
}

private struct SessionRipgrepPayload: Encodable {
    let args: [String]
    let cwd: String?
}

private struct SessionDifftasticPayload: Encodable {
    let args: [String]
    let cwd: String?
}

private struct SessionReadFilePayload: Encodable {
    let path: String
}

private struct SessionWriteFilePayload: Encodable {
    let path: String
    let content: String
    let expectedHash: String?
}

private struct SessionListDirectoryPayload: Encodable {
    let path: String
    let includeStats: Bool?
    let types: [String]?
    let sort: Bool?
    let maxEntries: Int?
}

private struct SessionsCodexThreadsResponse: Decodable {
    let success: Bool
    let threads: [APICodexThreadSummary]?
    let nextCursor: String?
    let hasNext: Bool?
}

private struct SessionsClaudeListResponse: Decodable {
    let success: Bool
    let sessions: [APIClaudeSessionSummary]?
    let nextCursor: String?
    let hasNext: Bool?
}

public actor URLSessionSessionsService: SessionsFetching, SessionsPagingFetching, SessionDeleting, SessionKilling {
    public init() {}
}
