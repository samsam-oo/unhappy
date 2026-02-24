import Foundation

public enum SessionsAPI {
    public static func makeListRequest(serverURL: URL, token: String) throws -> URLRequest {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw SessionsAPIError.missingToken
        }

        let sessionsURL = serverURL.appending(path: "v1/sessions")
        var request = URLRequest(url: sessionsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(normalizedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    public static func decodeListResponse(_ data: Data) throws -> [APISession] {
        let decoder = JSONDecoder()
        let response = try decoder.decode(SessionsListResponse.self, from: data)
        return response.sessions
    }
}

public enum SessionsAPIError: LocalizedError, Equatable {
    case missingToken
    case invalidHTTPStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .invalidHTTPStatus(let code):
            return "Request failed with status \(code)"
        }
    }
}

private struct SessionsListResponse: Decodable {
    let sessions: [APISession]
}

public protocol SessionsFetching: Sendable {
    func fetchSessions(serverURL: URL, token: String) async throws -> [APISession]
}

public struct URLSessionSessionsService: SessionsFetching {
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
}
