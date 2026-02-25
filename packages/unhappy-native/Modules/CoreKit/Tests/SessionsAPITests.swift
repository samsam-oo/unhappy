import Foundation
import Testing
@testable import CoreKit

struct SessionsAPITests {
    @Test
    func listRequestIncludesExpectedHeadersAndPath() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try SessionsAPI.makeListRequest(
            serverURL: baseURL,
            token: "abc123"
        )

        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/sessions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test
    func decodeListResponseParsesSessionRows() throws {
        let json = """
        {
          "sessions": [
            {
              "id": "s1",
              "active": true,
              "activeAt": 1700000000,
              "createdAt": 1699999900,
              "updatedAt": 1700000010,
              "metadataVersion": 1,
              "metadata": "ZW5jcnlwdGVk"
            }
          ]
        }
        """.data(using: .utf8)!

        let sessions = try SessionsAPI.decodeListResponse(json)

        #expect(sessions.count == 1)
        #expect(sessions.first?.id == "s1")
        #expect(sessions.first?.active == true)
        #expect(sessions.first?.metadataVersion == 1)
    }

    @Test
    func messagesRequestIncludesExpectedHeadersAndPath() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try SessionsAPI.makeMessagesRequest(
            serverURL: baseURL,
            token: "abc123",
            sessionID: "session-1"
        )

        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/sessions/session-1/messages")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
    }

    @Test
    func pagedListRequestIncludesExpectedQuery() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try SessionsAPI.makePagedListRequest(
            serverURL: baseURL,
            token: "abc123",
            cursor: "cursor_v1_abc",
            limit: 80
        )

        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v2/sessions?limit=80&cursor=cursor_v1_abc")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
    }

    @Test
    func decodePagedListResponseParsesPageRows() throws {
        let json = """
        {
          "sessions": [
            {
              "id": "s1",
              "seq": 10,
              "active": false,
              "activeAt": 1700000000,
              "createdAt": 1699999900,
              "updatedAt": 1700000010,
              "metadataVersion": 1,
              "metadata": "ZW5jcnlwdGVk",
              "agentState": null,
              "agentStateVersion": null,
              "dataEncryptionKey": null
            }
          ],
          "nextCursor": "cursor_v1_s1",
          "hasNext": true
        }
        """.data(using: .utf8)!

        let page = try SessionsAPI.decodePagedListResponse(json)

        #expect(page.sessions.count == 1)
        #expect(page.sessions.first?.id == "s1")
        #expect(page.sessions.first?.seq == 10)
        #expect(page.nextCursor == "cursor_v1_s1")
        #expect(page.hasNext == true)
    }

    @Test
    func decodeMessagesResponseParsesMessageRows() throws {
        let json = """
        {
          "messages": [
            {
              "id": "m1",
              "seq": 7,
              "localId": "l-1",
              "content": {
                "t": "encrypted",
                "c": "ZW5jcnlwdGVk"
              },
              "createdAt": 1700000001,
              "updatedAt": 1700000002
            }
          ]
        }
        """.data(using: .utf8)!

        let messages = try SessionsAPI.decodeMessagesResponse(json)

        #expect(messages.count == 1)
        #expect(messages.first?.id == "m1")
        #expect(messages.first?.seq == 7)
        #expect(messages.first?.localId == "l-1")
        #expect(messages.first?.content?.t == "encrypted")
    }

    @Test
    func deleteRequestUsesDeleteMethod() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try SessionsAPI.makeDeleteRequest(
            serverURL: baseURL,
            token: "abc123",
            sessionID: "session-1"
        )

        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/sessions/session-1")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
    }

    @Test
    func setTitleRequestUsesPatchMethodAndBody() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try SessionsAPI.makeSetTitleRequest(
            serverURL: baseURL,
            token: "abc123",
            sessionID: "session-1",
            title: "My Session"
        )

        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/sessions/session-1/title")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")

        let body = try #require(request.httpBody)
        let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(payload?["title"] as? String == "My Session")
    }

    @Test
    func setCodexTitleRequestUsesPatchMethodAndBody() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try SessionsAPI.makeSetCodexTitleRequest(
            serverURL: baseURL,
            token: "abc123",
            sessionID: "session-1",
            name: "Codex Session"
        )

        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/sessions/session-1/codex/title")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")

        let body = try #require(request.httpBody)
        let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(payload?["name"] as? String == "Codex Session")
    }

    @Test
    func requestWithoutSessionIDThrowsValidationError() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!

        #expect(throws: SessionsAPIError.missingSessionID) {
            _ = try SessionsAPI.makeMessagesRequest(
                serverURL: baseURL,
                token: "abc123",
                sessionID: "   "
            )
        }
    }

    @Test
    func codexTitleRequestWithoutNameThrowsValidationError() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!

        #expect(throws: SessionsAPIError.missingSessionTitle) {
            _ = try SessionsAPI.makeSetCodexTitleRequest(
                serverURL: baseURL,
                token: "abc123",
                sessionID: "session-1",
                name: "   "
            )
        }
    }

    @Test
    func codexThreadsRequestUsesExpectedPathAndQuery() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try SessionsAPI.makeCodexThreadsRequest(
            serverURL: baseURL,
            token: "abc123",
            sessionID: "session-1",
            limit: 33
        )

        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/sessions/session-1/codex/threads?limit=33")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
    }

    @Test
    func codexThreadsRequestIncludesCWDWhenProvided() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try SessionsAPI.makeCodexThreadsRequest(
            serverURL: baseURL,
            token: "abc123",
            sessionID: "session-1",
            limit: 20,
            cwd: "/tmp/workspace"
        )

        #expect(request.httpMethod == "GET")
        #expect(
            request.url?.absoluteString
                == "https://api.unhappy.im/v1/sessions/session-1/codex/threads?limit=20&cwd=/tmp/workspace"
        )
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
    }

    @Test
    func decodeCodexThreadsResponseParsesRows() throws {
        let json = """
        {
          "success": true,
          "threads": [
            {
              "id": "thread_1",
              "name": "Feature Work",
              "cwd": "/tmp/work",
              "updatedAt": "2026-02-24T10:00:00.000Z",
              "createdAt": "2026-02-24T09:00:00.000Z",
              "archived": false
            }
          ]
        }
        """.data(using: .utf8)!

        let threads = try SessionsAPI.decodeCodexThreadsResponse(json)

        #expect(threads.count == 1)
        #expect(threads.first?.id == "thread_1")
        #expect(threads.first?.name == "Feature Work")
        #expect(threads.first?.cwd == "/tmp/work")
    }

    @Test
    func claudeSessionsRequestUsesExpectedPathAndQuery() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try SessionsAPI.makeClaudeSessionsRequest(
            serverURL: baseURL,
            token: "abc123",
            sessionID: "session-1",
            limit: 12
        )

        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/sessions/session-1/claude/sessions?limit=12")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
    }

    @Test
    func claudeSessionsRequestIncludesCWDWhenProvided() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try SessionsAPI.makeClaudeSessionsRequest(
            serverURL: baseURL,
            token: "abc123",
            sessionID: "session-1",
            limit: 12,
            cwd: "/tmp/workspace"
        )

        #expect(request.httpMethod == "GET")
        #expect(
            request.url?.absoluteString
                == "https://api.unhappy.im/v1/sessions/session-1/claude/sessions?limit=12&cwd=/tmp/workspace"
        )
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
    }

    @Test
    func decodeClaudeSessionsResponseParsesRows() throws {
        let json = """
        {
          "success": true,
          "sessions": [
            {
              "id": "a1b2c3d4-1111-2222-3333-444444444444",
              "cwd": "/tmp/repo",
              "updatedAt": "2026-02-24T10:00:00.000Z",
              "createdAt": "2026-02-24T09:00:00.000Z"
            }
          ]
        }
        """.data(using: .utf8)!

        let sessions = try SessionsAPI.decodeClaudeSessionsResponse(json)

        #expect(sessions.count == 1)
        #expect(sessions.first?.id == "a1b2c3d4-1111-2222-3333-444444444444")
        #expect(sessions.first?.cwd == "/tmp/repo")
    }

    @Test
    func spawnSessionRequestUsesExpectedPathBodyAndMethod() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try SessionsAPI.makeSpawnSessionRequest(
            serverURL: baseURL,
            token: "abc123",
            sessionID: "session-1",
            directory: "/tmp/work",
            agent: .claude,
            codexResumeThreadID: nil,
            claudeResumeSessionID: "c7a2f5d1-1111-2222-3333-444444444444",
            approvedNewDirectoryCreation: true
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/sessions/session-1/spawn")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")

        let body = try #require(request.httpBody)
        let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(payload?["directory"] as? String == "/tmp/work")
        #expect(payload?["agent"] as? String == "claude")
        #expect(payload?["claudeResumeSessionId"] as? String == "c7a2f5d1-1111-2222-3333-444444444444")
        #expect(payload?["approvedNewDirectoryCreation"] as? Bool == true)
    }

    @Test
    func spawnSessionRequestWithoutDirectoryThrowsValidationError() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!

        #expect(throws: SessionsAPIError.missingDirectory) {
            _ = try SessionsAPI.makeSpawnSessionRequest(
                serverURL: baseURL,
                token: "abc123",
                sessionID: "session-1",
                directory: "   "
            )
        }
    }

    @Test
    func decodeSpawnSessionResponseParsesSuccessPayload() throws {
        let json = """
        {
          "success": true,
          "sessionId": "session-new"
        }
        """.data(using: .utf8)!

        let response = try SessionsAPI.decodeSpawnSessionResponse(json)
        #expect(response.success == true)
        #expect(response.sessionID == "session-new")
    }

    @Test
    func decodeSpawnSessionResponseParsesApprovalPayload() throws {
        let json = """
        {
          "success": false,
          "requiresUserApproval": true,
          "actionRequired": "CREATE_DIRECTORY",
          "directory": "/tmp/new-project"
        }
        """.data(using: .utf8)!

        let response = try SessionsAPI.decodeSpawnSessionResponse(json)
        #expect(response.success == false)
        #expect(response.requiresUserApproval == true)
        #expect(response.actionRequired == "CREATE_DIRECTORY")
        #expect(response.directory == "/tmp/new-project")
    }

    @Test
    func sessionBashRequestUsesExpectedPathAndBody() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try SessionsAPI.makeSessionBashRequest(
            serverURL: baseURL,
            token: "abc123",
            sessionID: "session-1",
            command: "ls -la",
            cwd: "/tmp/work",
            timeout: 20_000
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/sessions/session-1/commands/bash")

        let body = try #require(request.httpBody)
        let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(payload?["command"] as? String == "ls -la")
        #expect(payload?["cwd"] as? String == "/tmp/work")
        #expect(payload?["timeout"] as? Int == 20_000)
    }

    @Test
    func sessionReadFileRequestUsesExpectedPathAndBody() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try SessionsAPI.makeSessionReadFileRequest(
            serverURL: baseURL,
            token: "abc123",
            sessionID: "session-1",
            path: "/tmp/work/file.txt"
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/sessions/session-1/commands/read-file")

        let body = try #require(request.httpBody)
        let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(payload?["path"] as? String == "/tmp/work/file.txt")
    }

    @Test
    func sessionKillRequestUsesExpectedPathAndMethod() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try SessionsAPI.makeSessionKillRequest(
            serverURL: baseURL,
            token: "abc123",
            sessionID: "session-1"
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/sessions/session-1/kill")
    }

    @Test
    func decodeSessionReadFileResponseParsesPayload() throws {
        let json = """
        {
          "success": true,
          "content": "aGVsbG8="
        }
        """.data(using: .utf8)!

        let response = try SessionsAPI.decodeSessionReadFileResponse(json)
        #expect(response.success == true)
        #expect(response.content == "aGVsbG8=")
    }
}
