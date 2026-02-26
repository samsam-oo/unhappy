import Foundation

public enum APITerminalAuthRequestStatus: String, Decodable, Sendable {
    case notFound = "not_found"
    case pending
    case authorized
}

public struct APITerminalAuthStatus: Decodable, Equatable, Sendable {
    public let status: APITerminalAuthRequestStatus
    public let supportsV2: Bool

    public init(status: APITerminalAuthRequestStatus, supportsV2: Bool) {
        self.status = status
        self.supportsV2 = supportsV2
    }
}

public struct APITerminalAuthApproveResult: Decodable, Equatable, Sendable {
    public let success: Bool
    public let error: String?

    public init(success: Bool, error: String?) {
        self.success = success
        self.error = error
    }
}

public enum TerminalAuthAPI {
    public static func makeRequestStatusRequest(serverURL: URL, publicKeyBase64: String) throws -> URLRequest {
        let normalizedPublicKey = publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPublicKey.isEmpty else {
            throw TerminalAuthAPIError.missingPublicKey
        }

        let statusURL = serverURL.appending(path: "v1/auth/request/status")
        guard var components = URLComponents(url: statusURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        guard let encodedPublicKey = normalizedPublicKey.addingPercentEncoding(
            withAllowedCharacters: queryValueAllowedCharacters
        ) else {
            throw URLError(.badURL)
        }
        components.percentEncodedQuery = "publicKey=\(encodedPublicKey)"
        guard let requestURL = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    public static func makeApproveRequest(
        serverURL: URL,
        token: String,
        publicKeyBase64: String,
        responseBase64: String
    ) throws -> URLRequest {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw TerminalAuthAPIError.missingToken
        }
        let normalizedPublicKey = publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPublicKey.isEmpty else {
            throw TerminalAuthAPIError.missingPublicKey
        }
        let normalizedResponse = responseBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedResponse.isEmpty else {
            throw TerminalAuthAPIError.missingResponse
        }

        let responseURL = serverURL.appending(path: "v1/auth/response")
        var request = URLRequest(url: responseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(normalizedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = TerminalAuthApprovePayload(
            publicKey: normalizedPublicKey,
            response: normalizedResponse
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    public static func decodeStatusResponse(_ data: Data) throws -> APITerminalAuthStatus {
        let decoder = JSONDecoder()
        return try decoder.decode(APITerminalAuthStatus.self, from: data)
    }

    public static func decodeApproveResponse(_ data: Data) throws -> APITerminalAuthApproveResult {
        let decoder = JSONDecoder()
        return try decoder.decode(APITerminalAuthApproveResult.self, from: data)
    }
}

private let queryValueAllowedCharacters: CharacterSet = {
    var set = CharacterSet.alphanumerics
    set.insert(charactersIn: "-._~")
    return set
}()

public enum TerminalAuthAPIError: LocalizedError, Equatable {
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

private struct TerminalAuthApprovePayload: Encodable {
    let publicKey: String
    let response: String
}

public protocol TerminalAuthStatusChecking: Sendable {
    func fetchRequestStatus(serverURL: URL, publicKeyBase64: String) async throws -> APITerminalAuthStatus
}

public protocol TerminalAuthResponding: Sendable {
    func approveRequest(
        serverURL: URL,
        token: String,
        publicKeyBase64: String,
        responseBase64: String
    ) async throws -> APITerminalAuthApproveResult
}

public actor URLSessionTerminalAuthService: TerminalAuthStatusChecking, TerminalAuthResponding {
    public init() {}

    public func fetchRequestStatus(serverURL: URL, publicKeyBase64: String) async throws -> APITerminalAuthStatus {
        let request = try TerminalAuthAPI.makeRequestStatusRequest(
            serverURL: serverURL,
            publicKeyBase64: publicKeyBase64
        )
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TerminalAuthAPIError.invalidHTTPStatus(http.statusCode)
        }

        return try TerminalAuthAPI.decodeStatusResponse(data)
    }

    public func approveRequest(
        serverURL: URL,
        token: String,
        publicKeyBase64: String,
        responseBase64: String
    ) async throws -> APITerminalAuthApproveResult {
        let request = try TerminalAuthAPI.makeApproveRequest(
            serverURL: serverURL,
            token: token,
            publicKeyBase64: publicKeyBase64,
            responseBase64: responseBase64
        )
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TerminalAuthAPIError.invalidHTTPStatus(http.statusCode)
        }

        return try TerminalAuthAPI.decodeApproveResponse(data)
    }
}
