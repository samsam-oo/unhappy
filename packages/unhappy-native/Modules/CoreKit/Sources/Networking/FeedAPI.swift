import Foundation

public enum FeedAPI {
    public static func makeListRequest(
        serverURL: URL,
        token: String,
        before: String? = nil,
        after: String? = nil,
        limit: Int = 50
    ) throws -> URLRequest {
        let boundedLimit = min(max(limit, 1), 200)
        let feedURL = serverURL.appending(path: "v1/feed")
        guard var components = URLComponents(url: feedURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }

        var queryItems = [URLQueryItem(name: "limit", value: "\(boundedLimit)")]
        if let before = normalizedQueryValue(before) {
            queryItems.append(URLQueryItem(name: "before", value: before))
        }
        if let after = normalizedQueryValue(after) {
            queryItems.append(URLQueryItem(name: "after", value: after))
        }
        components.queryItems = queryItems

        guard let requestURL = components.url else {
            throw URLError(.badURL)
        }

        return try makeRequest(url: requestURL, method: "GET", token: token)
    }

    public static func decodeListResponse(_ data: Data) throws -> APIFeedPage {
        let decoder = JSONDecoder()
        let response = try decoder.decode(FeedListResponse.self, from: data)
        return APIFeedPage(items: response.items, hasMore: response.hasMore)
    }

    private static func makeRequest(url: URL, method: String, token: String) throws -> URLRequest {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw FeedAPIError.missingToken
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(normalizedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private static func normalizedQueryValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum FeedAPIError: LocalizedError, Equatable {
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

private struct FeedListResponse: Decodable {
    let items: [APIFeedItem]
    let hasMore: Bool
}

public protocol FeedFetching: Sendable {
    func fetchFeed(
        serverURL: URL,
        token: String,
        before: String?,
        after: String?,
        limit: Int
    ) async throws -> APIFeedPage
}

public actor URLSessionFeedService: FeedFetching {
    public init() {}

    public func fetchFeed(
        serverURL: URL,
        token: String,
        before: String?,
        after: String?,
        limit: Int
    ) async throws -> APIFeedPage {
        let request = try FeedAPI.makeListRequest(
            serverURL: serverURL,
            token: token,
            before: before,
            after: after,
            limit: limit
        )
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FeedAPIError.invalidHTTPStatus(http.statusCode)
        }

        return try FeedAPI.decodeListResponse(data)
    }
}
