import Foundation
import Testing
@testable import CoreKit

struct UsersAPITests {
    @Test
    func profileRequestIncludesExpectedHeadersAndPath() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try UsersAPI.makeProfileRequest(
            serverURL: baseURL,
            token: "abc123",
            userID: "user-1"
        )

        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/user/user-1")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test
    func searchRequestIncludesExpectedHeadersPathAndQuery() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try UsersAPI.makeSearchRequest(
            serverURL: baseURL,
            token: "abc123",
            query: "sky"
        )

        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/user/search?query=sky")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
    }

    @Test
    func decodeProfileResponseParsesUser() throws {
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

        let user = try UsersAPI.decodeProfileResponse(json)

        #expect(user?.id == "u1")
        #expect(user?.status == .friend)
    }

    @Test
    func decodeSearchResponseParsesUsers() throws {
        let json = """
        {
          "users": [
            {
              "id": "u1",
              "firstName": "Sky",
              "lastName": "Line",
              "avatar": null,
              "username": "skyline",
              "bio": null,
              "status": "none"
            }
          ]
        }
        """.data(using: .utf8)!

        let users = try UsersAPI.decodeSearchResponse(json)

        #expect(users.count == 1)
        #expect(users[0].id == "u1")
        #expect(users[0].status == .none)
    }

    @Test
    func profileRequestWithoutTokenThrowsValidationError() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!

        #expect(throws: UsersAPIError.missingToken) {
            _ = try UsersAPI.makeProfileRequest(
                serverURL: baseURL,
                token: " ",
                userID: "user-1"
            )
        }
    }

    @Test
    func profileRequestWithoutUserIDThrowsValidationError() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!

        #expect(throws: UsersAPIError.missingUserID) {
            _ = try UsersAPI.makeProfileRequest(
                serverURL: baseURL,
                token: "token",
                userID: " "
            )
        }
    }

    @Test
    func searchRequestWithoutQueryThrowsValidationError() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!

        #expect(throws: UsersAPIError.missingQuery) {
            _ = try UsersAPI.makeSearchRequest(
                serverURL: baseURL,
                token: "token",
                query: " "
            )
        }
    }
}
