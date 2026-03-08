import Foundation

extension URLSessionSessionsService {
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

    public func killSession(
        serverURL: URL,
        token: String,
        sessionID: String
    ) async throws -> APISessionKillResult {
        let request = try SessionsAPI.makeSessionKillRequest(
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

        return try SessionsAPI.decodeSessionKillResponse(data)
    }
}
