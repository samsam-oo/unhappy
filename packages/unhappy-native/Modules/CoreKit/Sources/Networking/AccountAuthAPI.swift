import Foundation

public enum AccountAuthAPI {
    public static func makeApproveRequest(
        serverURL: URL,
        token: String,
        publicKeyBase64: String,
        responseBase64: String
    ) throws -> URLRequest {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw AccountAuthAPIError.missingToken
        }
        let normalizedPublicKey = publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPublicKey.isEmpty else {
            throw AccountAuthAPIError.missingPublicKey
        }
        let normalizedResponse = responseBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedResponse.isEmpty else {
            throw AccountAuthAPIError.missingResponse
        }

        let responseURL = serverURL.appending(path: "v1/auth/account/response")
        var request = URLRequest(url: responseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(normalizedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = AccountAuthApprovePayload(
            publicKey: normalizedPublicKey,
            response: normalizedResponse
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }
}

public enum AccountAuthAPIError: LocalizedError, Equatable {
    case missingToken
    case missingPublicKey
    case missingResponse
    case invalidHTTPStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .missingPublicKey:
            return "Public key is required"
        case .missingResponse:
            return "Encrypted response is required"
        case .invalidHTTPStatus(let code):
            return "Request failed with status \(code)"
        }
    }
}

private struct AccountAuthApprovePayload: Encodable {
    let publicKey: String
    let response: String
}

public protocol AccountAuthResponding: Sendable {
    func approveAccountRequest(
        serverURL: URL,
        token: String,
        publicKeyBase64: String,
        responseBase64: String
    ) async throws
}

public actor URLSessionAccountAuthService: AccountAuthResponding {
    public init() {}

    public func approveAccountRequest(
        serverURL: URL,
        token: String,
        publicKeyBase64: String,
        responseBase64: String
    ) async throws {
        let request = try AccountAuthAPI.makeApproveRequest(
            serverURL: serverURL,
            token: token,
            publicKeyBase64: publicKeyBase64,
            responseBase64: responseBase64
        )
        let (_, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AccountAuthAPIError.invalidHTTPStatus(http.statusCode)
        }
    }
}
