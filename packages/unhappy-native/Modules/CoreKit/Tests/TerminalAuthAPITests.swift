import Foundation
import Testing
@testable import CoreKit

struct TerminalAuthAPITests {
    @Test
    func statusRequestBuildsExpectedURL() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try TerminalAuthAPI.makeRequestStatusRequest(
            serverURL: baseURL,
            publicKeyBase64: "abc+/123=="
        )

        #expect(request.httpMethod == "GET")
        #expect(
            request.url?.absoluteString
                == "https://api.unhappy.im/v1/auth/request/status?publicKey=abc%2B%2F123%3D%3D"
        )
    }

    @Test
    func approveRequestBuildsExpectedHeadersBodyAndPath() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!
        let request = try TerminalAuthAPI.makeApproveRequest(
            serverURL: baseURL,
            token: "token-123",
            publicKeyBase64: "cHVibGlj",
            responseBase64: "ZW5jcnlwdGVk"
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/auth/response")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-123")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(payload?["publicKey"] as? String == "cHVibGlj")
        #expect(payload?["response"] as? String == "ZW5jcnlwdGVk")
    }

    @Test
    func decodeStatusResponseParsesStatusFields() throws {
        let json = """
        {
          "status": "pending",
          "supportsV2": true
        }
        """.data(using: .utf8)!

        let status = try TerminalAuthAPI.decodeStatusResponse(json)

        #expect(status.status == .pending)
        #expect(status.supportsV2 == true)
    }

    @Test
    func decodeApproveResponseParsesSuccess() throws {
        let json = """
        {
          "success": true
        }
        """.data(using: .utf8)!

        let result = try TerminalAuthAPI.decodeApproveResponse(json)

        #expect(result.success == true)
        #expect(result.error == nil)
    }

    @Test
    func statusRequestWithoutPublicKeyThrowsValidationError() throws {
        let baseURL = URL(string: "https://api.unhappy.im")!

        #expect(throws: TerminalAuthAPIError.missingPublicKey) {
            _ = try TerminalAuthAPI.makeRequestStatusRequest(
                serverURL: baseURL,
                publicKeyBase64: "   "
            )
        }
    }
}
