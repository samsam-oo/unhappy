import Foundation
import Testing
@testable import CoreKit

struct AccountAuthAPITests {
    @Test
    func makeApproveRequestBuildsExpectedPayload() throws {
        let request = try AccountAuthAPI.makeApproveRequest(
            serverURL: URL(string: "https://api.unhappy.im")!,
            token: "token-123",
            publicKeyBase64: "cHVibGlj",
            responseBase64: "ZW5jcnlwdGVk"
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/auth/account/response")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-123")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        guard let body = request.httpBody else {
            Issue.record("missing request body")
            return
        }
        let json = try JSONSerialization.jsonObject(with: body) as? [String: String]
        #expect(json?["publicKey"] == "cHVibGlj")
        #expect(json?["response"] == "ZW5jcnlwdGVk")
    }

    @Test
    func makeApproveRequestRejectsMissingInputs() {
        #expect(throws: AccountAuthAPIError.missingToken) {
            _ = try AccountAuthAPI.makeApproveRequest(
                serverURL: URL(string: "https://api.unhappy.im")!,
                token: "   ",
                publicKeyBase64: "abc",
                responseBase64: "def"
            )
        }
        #expect(throws: AccountAuthAPIError.missingPublicKey) {
            _ = try AccountAuthAPI.makeApproveRequest(
                serverURL: URL(string: "https://api.unhappy.im")!,
                token: "token",
                publicKeyBase64: " ",
                responseBase64: "def"
            )
        }
        #expect(throws: AccountAuthAPIError.missingResponse) {
            _ = try AccountAuthAPI.makeApproveRequest(
                serverURL: URL(string: "https://api.unhappy.im")!,
                token: "token",
                publicKeyBase64: "abc",
                responseBase64: " "
            )
        }
    }
}
