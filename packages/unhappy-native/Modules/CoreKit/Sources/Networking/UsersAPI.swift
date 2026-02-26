import Foundation

public enum UsersAPI {
    public static func makeProfileRequest(
        serverURL: URL,
        token: String,
        userID: String
    ) throws -> URLRequest {
        let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUserID.isEmpty else {
            throw UsersAPIError.missingUserID
        }
        let profileURL = serverURL.appending(path: "v1/user/\(normalizedUserID)")
        return try makeRequest(url: profileURL, method: "GET", token: token)
    }

    public static func makeSearchRequest(
        serverURL: URL,
        token: String,
        query: String
    ) throws -> URLRequest {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            throw UsersAPIError.missingQuery
        }
        let searchURL = serverURL.appending(path: "v1/user/search")
        guard var components = URLComponents(url: searchURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "query", value: normalizedQuery)]
        guard let requestURL = components.url else {
            throw URLError(.badURL)
        }
        return try makeRequest(url: requestURL, method: "GET", token: token)
    }

    public static func decodeProfileResponse(_ data: Data) throws -> APIUserProfile? {
        let decoder = JSONDecoder()
        let response = try decoder.decode(UserProfileResponse.self, from: data)
        return response.user
    }

    public static func decodeSearchResponse(_ data: Data) throws -> [APIUserProfile] {
        let decoder = JSONDecoder()
        let response = try decoder.decode(UserSearchResponse.self, from: data)
        return response.users
    }

    private static func makeRequest(url: URL, method: String, token: String) throws -> URLRequest {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw UsersAPIError.missingToken
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(normalizedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
}

public enum UsersAPIError: LocalizedError, Equatable {
    case missingToken
    case missingUserID
    case missingQuery
    case invalidHTTPStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .missingUserID:
            return "User ID is required"
        case .missingQuery:
            return "Query is required"
        case .invalidHTTPStatus(let code):
            return "Request failed with status \(code)"
        }
    }
}

private struct UserProfileResponse: Decodable {
    let user: APIUserProfile?
}

private struct UserSearchResponse: Decodable {
    let users: [APIUserProfile]
}

public protocol UserProfileFetching: Sendable {
    func fetchUserProfile(
        serverURL: URL,
        token: String,
        userID: String
    ) async throws -> APIUserProfile?
}

public protocol UserSearchFetching: Sendable {
    func searchUsers(
        serverURL: URL,
        token: String,
        query: String
    ) async throws -> [APIUserProfile]
}

public actor URLSessionUsersService: UserProfileFetching, UserSearchFetching {
    public init() {}

    public func fetchUserProfile(
        serverURL: URL,
        token: String,
        userID: String
    ) async throws -> APIUserProfile? {
        let request = try UsersAPI.makeProfileRequest(
            serverURL: serverURL,
            token: token,
            userID: userID
        )
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 404 {
            return nil
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UsersAPIError.invalidHTTPStatus(http.statusCode)
        }

        return try UsersAPI.decodeProfileResponse(data)
    }

    public func searchUsers(
        serverURL: URL,
        token: String,
        query: String
    ) async throws -> [APIUserProfile] {
        let request = try UsersAPI.makeSearchRequest(
            serverURL: serverURL,
            token: token,
            query: query
        )
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 404 {
            return []
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UsersAPIError.invalidHTTPStatus(http.statusCode)
        }

        return try UsersAPI.decodeSearchResponse(data)
    }
}
