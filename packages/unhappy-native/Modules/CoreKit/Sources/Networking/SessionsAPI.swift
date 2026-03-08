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

    public static func decodePagedListResponse(_ data: Data) throws -> APISessionsPage {
        let decoder = JSONDecoder()
        let response = try decoder.decode(SessionsPagedListResponse.self, from: data)
        return APISessionsPage(
            sessions: response.sessions,
            nextCursor: response.nextCursor,
            hasNext: response.hasNext
        )
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

private struct SessionsPagedListResponse: Decodable {
    let sessions: [APISession]
    let nextCursor: String?
    let hasNext: Bool
}

public actor URLSessionSessionsService: SessionsFetching, SessionsPagingFetching, SessionDeleting {
    public init() {}
}
