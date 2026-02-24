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
}
