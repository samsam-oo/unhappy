import Foundation

public enum FriendsAPI {
    public static func makeListRequest(serverURL: URL, token: String) throws -> URLRequest {
        let friendsURL = serverURL.appending(path: "v1/friends")
        return try makeRequest(url: friendsURL, method: "GET", token: token)
    }

    public static func decodeListResponse(_ data: Data) throws -> [APIUserProfile] {
        let decoder = JSONDecoder()
        let response = try decoder.decode(FriendsListResponse.self, from: data)
        return response.friends
    }

    private static func makeRequest(url: URL, method: String, token: String) throws -> URLRequest {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw FriendsAPIError.missingToken
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(normalizedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
}

public enum FriendsAPIError: LocalizedError, Equatable {
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

private struct FriendsListResponse: Decodable {
    let friends: [APIUserProfile]
}

public protocol FriendsFetching: Sendable {
    func fetchFriends(serverURL: URL, token: String) async throws -> [APIUserProfile]
}

public actor URLSessionFriendsService: FriendsFetching {
    public init() {}

    public func fetchFriends(serverURL: URL, token: String) async throws -> [APIUserProfile] {
        let request = try FriendsAPI.makeListRequest(serverURL: serverURL, token: token)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FriendsAPIError.invalidHTTPStatus(http.statusCode)
        }

        return try FriendsAPI.decodeListResponse(data)
    }
}
