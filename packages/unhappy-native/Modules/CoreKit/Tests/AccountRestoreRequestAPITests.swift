import Foundation
import Testing
@testable import CoreKit

struct AccountRestoreRequestAPITests {
    @Test
    func makeRequestBuildsExpectedPayload() throws {
        let request = try AccountRestoreRequestAPI.makeRequest(
            serverURL: URL(string: "https://api.unhappy.im")!,
            publicKeyBase64: "publicKeyBase64==",
            supportsEncryptedToken: true
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.unhappy.im/v1/auth/account/request")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        guard let body = request.httpBody else {
            Issue.record("missing request body")
            return
        }
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["publicKey"] as? String == "publicKeyBase64==")
        #expect(json?["supportsEncryptedToken"] as? Bool == true)
    }

    @Test
    func makeRequestRejectsMissingPublicKey() {
        #expect(throws: AccountRestoreRequestAPIError.missingPublicKey) {
            _ = try AccountRestoreRequestAPI.makeRequest(
                serverURL: URL(string: "https://api.unhappy.im")!,
                publicKeyBase64: " ",
                supportsEncryptedToken: true
            )
        }
    }

    @Test
    func decodeStatusResponseParsesAuthorized() throws {
        let json = Data(
            #"{"state":"authorized","response":"r","token":"t","encryptedToken":"et"}"#.utf8
        )

        let status = try AccountRestoreRequestAPI.decodeStatusResponse(json)

        #expect(status.state == "authorized")
        #expect(status.response == "r")
        #expect(status.token == "t")
        #expect(status.encryptedToken == "et")
    }
}
