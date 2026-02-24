import Foundation

public enum SessionsAPI {
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

    public static func decodeListResponse(_ data: Data) throws -> [APISession] {
        let decoder = JSONDecoder()
        let response = try decoder.decode(SessionsListResponse.self, from: data)
        return response.sessions
    }

    public static func decodeMessagesResponse(_ data: Data) throws -> [APISessionMessage] {
        let decoder = JSONDecoder()
        let response = try decoder.decode(SessionsMessagesResponse.self, from: data)
        return response.messages
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

public protocol SessionsFetching: Sendable {
    func fetchSessions(serverURL: URL, token: String) async throws -> [APISession]
}

public protocol SessionMessagesFetching: Sendable {
    func fetchSessionMessages(serverURL: URL, token: String, sessionID: String) async throws -> [APISessionMessage]
}

public protocol SessionDeleting: Sendable {
    func deleteSession(serverURL: URL, token: String, sessionID: String) async throws
}

public actor URLSessionSessionsService: SessionsFetching, SessionMessagesFetching, SessionDeleting {
    public init() {}

    public func fetchSessions(serverURL: URL, token: String) async throws -> [APISession] {
        let request = try SessionsAPI.makeListRequest(serverURL: serverURL, token: token)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SessionsAPIError.invalidHTTPStatus(http.statusCode)
        }

        return try SessionsAPI.decodeListResponse(data)
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
}
