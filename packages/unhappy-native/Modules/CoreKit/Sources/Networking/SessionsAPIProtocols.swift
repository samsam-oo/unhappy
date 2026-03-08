import Foundation

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

public protocol SessionDeleting: Sendable {
    func deleteSession(serverURL: URL, token: String, sessionID: String) async throws
}

public protocol SessionKilling: Sendable {
    func killSession(
        serverURL: URL,
        token: String,
        sessionID: String
    ) async throws -> APISessionKillResult
}
