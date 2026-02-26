import Foundation
import Testing
@testable import CoreKit

struct FriendsAPITests {
    @Test
    func listRequestIncludesExpectedHeadersAndPath() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try FriendsAPI.makeListRequest(
            serverURL: baseURL,
            token: "abc123"
        )

        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/friends")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test
    func addRequestIncludesExpectedHeadersPathAndBody() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try FriendsAPI.makeAddRequest(
            serverURL: baseURL,
            token: "abc123",
            userID: "user-1"
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/friends/add")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
        let body = try #require(request.httpBody)
        let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(payload?["uid"] as? String == "user-1")
    }

    @Test
    func removeRequestIncludesExpectedHeadersPathAndBody() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try FriendsAPI.makeRemoveRequest(
            serverURL: baseURL,
            token: "abc123",
            userID: "user-2"
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/friends/remove")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
        let body = try #require(request.httpBody)
        let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(payload?["uid"] as? String == "user-2")
    }

    @Test
    func decodeListResponseParsesRows() throws {
        let json = """
        {
          "friends": [
            {
              "id": "u1",
              "firstName": "Sky",
              "lastName": "Line",
              "avatar": null,
              "username": "skyline",
              "bio": null,
              "status": "pending"
            },
            {
              "id": "u2",
              "firstName": "",
              "lastName": null,
              "avatar": null,
              "username": "coder2",
              "bio": "bio",
              "status": "friend"
            }
          ]
        }
        """.data(using: .utf8)!

        let rows = try FriendsAPI.decodeListResponse(json)

        #expect(rows.count == 2)
        #expect(rows[0].status == .pending)
        #expect(rows[0].displayName == "Sky Line")
        #expect(rows[1].status == .friend)
        #expect(rows[1].displayName == "coder2")
    }

    @Test
    func decodeMutationResponseParsesUser() throws {
        let json = """
        {
          "user": {
            "id": "u1",
            "firstName": "Sky",
            "lastName": "Line",
            "avatar": null,
            "username": "skyline",
            "bio": null,
            "status": "friend"
          }
        }
        """.data(using: .utf8)!

        let user = try FriendsAPI.decodeMutationResponse(json)

        #expect(user?.id == "u1")
        #expect(user?.status == .friend)
    }

    @Test
    func listRequestWithoutTokenThrowsValidationError() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!

        #expect(throws: FriendsAPIError.missingToken) {
            _ = try FriendsAPI.makeListRequest(
                serverURL: baseURL,
                token: " "
            )
        }
    }

    @Test
    func mutationRequestWithoutUserIDThrowsValidationError() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!

        #expect(throws: FriendsAPIError.missingUserID) {
            _ = try FriendsAPI.makeAddRequest(
                serverURL: baseURL,
                token: "token",
                userID: " "
            )
        }
    }
}
