import Foundation
import Testing
@testable import CoreKit

struct FeedAPITests {
    @Test
    func listRequestIncludesExpectedHeadersAndQuery() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try FeedAPI.makeListRequest(
            serverURL: baseURL,
            token: "abc123",
            before: "0-10",
            after: "0-30",
            limit: 80
        )

        #expect(request.httpMethod == "GET")
        #expect(
            request.url?.absoluteString
            == "https://api.unhappy.im/v1/feed?limit=80&before=0-10&after=0-30"
        )
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test
    func listRequestClampsLimit() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try FeedAPI.makeListRequest(
            serverURL: baseURL,
            token: "abc123",
            limit: 500
        )

        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/feed?limit=200")
    }

    @Test
    func decodeListResponseParsesRows() throws {
        let json = """
        {
          "items": [
            {
              "id": "f1",
              "body": { "kind": "friend_request", "uid": "user_a" },
              "repeatKey": null,
              "cursor": "0-10",
              "createdAt": 1735689600000
            },
            {
              "id": "f2",
              "body": { "kind": "friend_accepted", "uid": "user_b" },
              "repeatKey": "rk-1",
              "cursor": "0-11",
              "createdAt": 1735689700000
            },
            {
              "id": "f3",
              "body": { "kind": "text", "text": "Daemon updated" },
              "repeatKey": null,
              "cursor": "0-12",
              "createdAt": 1735689800000
            }
          ],
          "hasMore": true
        }
        """.data(using: .utf8)!

        let page = try FeedAPI.decodeListResponse(json)

        #expect(page.items.count == 3)
        #expect(page.hasMore == true)
        #expect(page.items[0].id == "f1")
        #expect(page.items[0].body == .friendRequest(uid: "user_a"))
        #expect(page.items[1].body == .friendAccepted(uid: "user_b"))
        #expect(page.items[2].body == .text(text: "Daemon updated"))
    }

    @Test
    func listRequestWithoutTokenThrowsValidationError() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!

        #expect(throws: FeedAPIError.missingToken) {
            _ = try FeedAPI.makeListRequest(
                serverURL: baseURL,
                token: "   "
            )
        }
    }
}
