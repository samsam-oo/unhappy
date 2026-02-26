import Foundation

public enum FriendsAPI {
    public static func makeListRequest(serverURL: URL, token: String) throws -> URLRequest {
        let friendsURL = serverURL.appending(path: "v1/friends")
        return try makeRequest(url: friendsURL, method: "GET", token: token)
    }

    public static func makeAddRequest(
        serverURL: URL,
        token: String,
        userID: String
    ) throws -> URLRequest {
        let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUserID.isEmpty else {
            throw FriendsAPIError.missingUserID
        }
        let addURL = serverURL.appending(path: "v1/friends/add")
        var request = try makeRequest(url: addURL, method: "POST", token: token)
        request.httpBody = try JSONEncoder().encode(FriendMutationPayload(uid: normalizedUserID))
        return request
    }

    public static func makeRemoveRequest(
        serverURL: URL,
        token: String,
        userID: String
    ) throws -> URLRequest {
        let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUserID.isEmpty else {
            throw FriendsAPIError.missingUserID
        }
        let removeURL = serverURL.appending(path: "v1/friends/remove")
        var request = try makeRequest(url: removeURL, method: "POST", token: token)
        request.httpBody = try JSONEncoder().encode(FriendMutationPayload(uid: normalizedUserID))
        return request
    }

    public static func decodeListResponse(_ data: Data) throws -> [APIUserProfile] {
        let decoder = JSONDecoder()
        let response = try decoder.decode(FriendsListResponse.self, from: data)
        return response.friends
    }

    public static func decodeMutationResponse(_ data: Data) throws -> APIUserProfile? {
        let decoder = JSONDecoder()
        let response = try decoder.decode(FriendMutationResponse.self, from: data)
        return response.user
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
    case missingUserID
    case invalidHTTPStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .missingUserID:
            return "User ID is required"
        case .invalidHTTPStatus(let code):
            return "Request failed with status \(code)"
        }
    }
}

private struct FriendsListResponse: Decodable {
    let friends: [APIUserProfile]
}

private struct FriendMutationResponse: Decodable {
    let user: APIUserProfile?
}

private struct FriendMutationPayload: Encodable {
    let uid: String
}

public protocol FriendsFetching: Sendable {
    func fetchFriends(serverURL: URL, token: String) async throws -> [APIUserProfile]
}

public protocol FriendAdding: Sendable {
    func addFriend(
        serverURL: URL,
        token: String,
        userID: String
    ) async throws -> APIUserProfile?
}

public protocol FriendRemoving: Sendable {
    func removeFriend(
        serverURL: URL,
        token: String,
        userID: String
    ) async throws -> APIUserProfile?
}

public actor URLSessionFriendsService: FriendsFetching, FriendAdding, FriendRemoving {
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

    public func addFriend(
        serverURL: URL,
        token: String,
        userID: String
    ) async throws -> APIUserProfile? {
        let request = try FriendsAPI.makeAddRequest(
            serverURL: serverURL,
            token: token,
            userID: userID
        )
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FriendsAPIError.invalidHTTPStatus(http.statusCode)
        }

        return try FriendsAPI.decodeMutationResponse(data)
    }

    public func removeFriend(
        serverURL: URL,
        token: String,
        userID: String
    ) async throws -> APIUserProfile? {
        let request = try FriendsAPI.makeRemoveRequest(
            serverURL: serverURL,
            token: token,
            userID: userID
        )
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FriendsAPIError.invalidHTTPStatus(http.statusCode)
        }

        return try FriendsAPI.decodeMutationResponse(data)
    }
}
