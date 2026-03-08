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
    func decodeListResponseParsesSessionRows() throws {
        let json = """
        {
          "sessions": [
            {
              "id": "s1",
              "displayName": "Session One",
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
        #expect(sessions.first?.displayName == "Session One")
        #expect(sessions.first?.active == true)
        #expect(sessions.first?.metadataVersion == 1)
    }

    @Test
    func decodeListResponseRepairsMojibakeDisplayName() throws {
        let json = """
        {
          "sessions": [
            {
              "id": "s1",
              "displayName": "ìë",
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
        #expect(sessions.first?.displayName == "안녕")
    }

    @Test
    func decodeListResponseNormalizesMillisecondTimestampsToSeconds() throws {
        let json = """
        {
          "sessions": [
            {
              "id": "s1",
              "active": true,
              "activeAt": 1700000000000,
              "createdAt": 1699999900000,
              "updatedAt": 1700000010000,
              "metadataVersion": 1,
              "metadata": "ZW5jcnlwdGVk"
            }
          ]
        }
        """.data(using: .utf8)!

        let sessions = try SessionsAPI.decodeListResponse(json)
        let row = try #require(sessions.first)

        #expect(row.activeAt == 1_700_000_000)
        #expect(row.createdAt == 1_699_999_900)
        #expect(row.updatedAt == 1_700_000_010)
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
}
