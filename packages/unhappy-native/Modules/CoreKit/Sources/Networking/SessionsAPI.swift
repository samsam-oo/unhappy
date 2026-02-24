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

    public static func makeCodexThreadsRequest(
        serverURL: URL,
        token: String,
        sessionID: String,
        limit: Int = 20
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
        components.queryItems = [
            URLQueryItem(name: "limit", value: "\(boundedLimit)")
        ]
        guard let requestURL = components.url else {
            throw URLError(.badURL)
        }
        return try makeRequest(
            url: requestURL,
            method: "GET",
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
        let response = try decoder.decode(SessionsMessagesResponse.self, from: data)
        return response.messages
    }

    public static func decodeCodexThreadsResponse(_ data: Data) throws -> [APICodexThreadSummary] {
        let decoder = JSONDecoder()
        let response = try decoder.decode(SessionsCodexThreadsResponse.self, from: data)
        return response.threads
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
    case invalidHTTPStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .missingSessionID:
            return "Session ID is required"
        case .invalidHTTPStatus(let code):
            return "Request failed with status \(code)"
        }
    }
}

private struct SessionsListResponse: Decodable {
    let sessions: [APISession]
}

private struct SessionsMessagesResponse: Decodable {
    let messages: [APISessionMessage]
}

private struct SessionsPagedListResponse: Decodable {
    let sessions: [APISession]
    let nextCursor: String?
    let hasNext: Bool
}

private struct SessionTitlePayload: Encodable {
    let title: String?
}

private struct SessionsCodexThreadsResponse: Decodable {
    let success: Bool
    let threads: [APICodexThreadSummary]
}

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
        limit: Int
    ) async throws -> [APICodexThreadSummary]
}

public actor URLSessionSessionsService: SessionsFetching, SessionsPagingFetching, SessionMessagesFetching, SessionDeleting, SessionTitleUpdating, SessionCodexThreadsFetching {
    public init() {}

    public func fetchSessions(serverURL: URL, token: String) async throws -> [APISession] {
        let page = try await fetchSessionsPage(
            serverURL: serverURL,
            token: token,
            cursor: nil,
            limit: 50
        )
        return page.sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func fetchSessionsPage(
        serverURL: URL,
        token: String,
        cursor: String?,
        limit: Int
    ) async throws -> APISessionsPage {
        let request = try SessionsAPI.makePagedListRequest(
            serverURL: serverURL,
            token: token,
            cursor: cursor,
            limit: limit
        )
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SessionsAPIError.invalidHTTPStatus(http.statusCode)
        }

        return try SessionsAPI.decodePagedListResponse(data)
    }

    public func fetchSessionMessages(serverURL: URL, token: String, sessionID: String) async throws -> [APISessionMessage] {
        let request = try SessionsAPI.makeMessagesRequest(
            serverURL: serverURL,
            token: token,
            sessionID: sessionID
        )
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SessionsAPIError.invalidHTTPStatus(http.statusCode)
        }

        return try SessionsAPI.decodeMessagesResponse(data)
    }

    public func deleteSession(serverURL: URL, token: String, sessionID: String) async throws {
        let request = try SessionsAPI.makeDeleteRequest(
            serverURL: serverURL,
            token: token,
            sessionID: sessionID
        )
        let (_, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 404 {
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SessionsAPIError.invalidHTTPStatus(http.statusCode)
        }
    }

    public func setSessionTitle(serverURL: URL, token: String, sessionID: String, title: String?) async throws {
        let request = try SessionsAPI.makeSetTitleRequest(
            serverURL: serverURL,
            token: token,
            sessionID: sessionID,
            title: title
        )
        let (_, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SessionsAPIError.invalidHTTPStatus(http.statusCode)
        }
    }

    public func fetchCodexThreads(
        serverURL: URL,
        token: String,
        sessionID: String,
        limit: Int
    ) async throws -> [APICodexThreadSummary] {
        let request = try SessionsAPI.makeCodexThreadsRequest(
            serverURL: serverURL,
            token: token,
            sessionID: sessionID,
            limit: limit
        )
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SessionsAPIError.invalidHTTPStatus(http.statusCode)
        }

        return try SessionsAPI.decodeCodexThreadsResponse(data)
    }
}
