import Foundation

public struct APIAccountRestoreRequestStatus: Decodable, Equatable, Sendable {
    public let state: String
    public let response: String?
    public let token: String?
    public let encryptedToken: String?

    public init(
        state: String,
        response: String?,
        token: String?,
        encryptedToken: String?
    ) {
        self.state = state
        self.response = response
        self.token = token
        self.encryptedToken = encryptedToken
    }
}

public enum AccountRestoreRequestAPI {
    public static func makeRequest(
        serverURL: URL,
        publicKeyBase64: String,
        supportsEncryptedToken: Bool
    ) throws -> URLRequest {
        let normalizedPublicKey = publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPublicKey.isEmpty else {
            throw AccountRestoreRequestAPIError.missingPublicKey
        }

        let requestURL = serverURL.appending(path: "v1/auth/account/request")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = AccountRestoreRequestPayload(
            publicKey: normalizedPublicKey,
            supportsEncryptedToken: supportsEncryptedToken
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    public static func decodeStatusResponse(_ data: Data) throws -> APIAccountRestoreRequestStatus {
        let decoder = JSONDecoder()
        return try decoder.decode(APIAccountRestoreRequestStatus.self, from: data)
    }
}

public enum AccountRestoreRequestAPIError: LocalizedError, Equatable {
    case missingPublicKey
    case invalidHTTPStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .missingPublicKey:
            return "Public key is required"
        case .invalidHTTPStatus(let code):
            return "Request failed with status \(code)"
        }
    }
}

private struct AccountRestoreRequestPayload: Encodable {
    let publicKey: String
    let supportsEncryptedToken: Bool
}

public protocol AccountRestoreRequestPolling: Sendable {
    func fetchAccountRestoreRequestStatus(
        serverURL: URL,
        publicKeyBase64: String,
        supportsEncryptedToken: Bool
    ) async throws -> APIAccountRestoreRequestStatus
}

public actor URLSessionAccountRestoreRequestService: AccountRestoreRequestPolling {
    public init() {}

    public func fetchAccountRestoreRequestStatus(
        serverURL: URL,
        publicKeyBase64: String,
        supportsEncryptedToken: Bool
    ) async throws -> APIAccountRestoreRequestStatus {
        let request = try AccountRestoreRequestAPI.makeRequest(
            serverURL: serverURL,
            publicKeyBase64: publicKeyBase64,
            supportsEncryptedToken: supportsEncryptedToken
        )
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AccountRestoreRequestAPIError.invalidHTTPStatus(http.statusCode)
        }

        return try AccountRestoreRequestAPI.decodeStatusResponse(data)
    }
}
