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
}
