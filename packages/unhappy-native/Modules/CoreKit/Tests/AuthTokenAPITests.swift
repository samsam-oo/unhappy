import Foundation
import Testing
@testable import CoreKit

struct AuthTokenAPITests {
    @Test
    func makeTokenRequestBuildsExpectedPayload() throws {
        let request = try AuthTokenAPI.makeTokenRequest(
            serverURL: URL(string: "https://api.unhappy.im")!,
            challengeBase64: "challenge",
            signatureBase64: "signature",
            publicKeyBase64: "publicKey"
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/auth")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        guard let body = request.httpBody else {
            Issue.record("missing request body")
            return
        }
        let json = try JSONSerialization.jsonObject(with: body) as? [String: String]
        #expect(json?["challenge"] == "challenge")
        #expect(json?["signature"] == "signature")
        #expect(json?["publicKey"] == "publicKey")
    }

    @Test
    func makeTokenRequestRejectsMissingFields() {
        #expect(throws: AuthTokenAPIError.missingChallenge) {
            _ = try AuthTokenAPI.makeTokenRequest(
                serverURL: URL(string: "https://api.unhappy.im")!,
                challengeBase64: " ",
                signatureBase64: "sig",
                publicKeyBase64: "pk"
            )
        }
        #expect(throws: AuthTokenAPIError.missingSignature) {
            _ = try AuthTokenAPI.makeTokenRequest(
                serverURL: URL(string: "https://api.unhappy.im")!,
                challengeBase64: "challenge",
                signatureBase64: " ",
                publicKeyBase64: "pk"
            )
        }
        #expect(throws: AuthTokenAPIError.missingPublicKey) {
            _ = try AuthTokenAPI.makeTokenRequest(
                serverURL: URL(string: "https://api.unhappy.im")!,
                challengeBase64: "challenge",
                signatureBase64: "sig",
                publicKeyBase64: " "
            )
        }
    }

    @Test
    func decodeTokenResponseParsesToken() throws {
        let json = Data(#"{"token":"abc"}"#.utf8)
        let token = try AuthTokenAPI.decodeTokenResponse(json)
        #expect(token == "abc")
    }

    @Test
    func decodeTokenResponseRejectsEmptyToken() {
        let json = Data(#"{"token":" "}"#.utf8)
        #expect(throws: AuthTokenAPIError.missingTokenInResponse) {
            _ = try AuthTokenAPI.decodeTokenResponse(json)
        }
    }
}
