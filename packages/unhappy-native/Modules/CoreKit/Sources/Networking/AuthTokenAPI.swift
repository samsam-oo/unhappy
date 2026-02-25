import Foundation
import CryptoKit
import Security

public enum AuthTokenAPI {
    public static func makeTokenRequest(
        serverURL: URL,
        challengeBase64: String,
        signatureBase64: String,
        publicKeyBase64: String
    ) throws -> URLRequest {
        let normalizedChallenge = challengeBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedChallenge.isEmpty else {
            throw AuthTokenAPIError.missingChallenge
        }
        let normalizedSignature = signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSignature.isEmpty else {
            throw AuthTokenAPIError.missingSignature
        }
        let normalizedPublicKey = publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPublicKey.isEmpty else {
            throw AuthTokenAPIError.missingPublicKey
        }

        let requestURL = serverURL.appending(path: "v1/auth")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = AuthTokenRequestPayload(
            challenge: normalizedChallenge,
            signature: normalizedSignature,
            publicKey: normalizedPublicKey
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    public static func decodeTokenResponse(_ data: Data) throws -> String {
        let decoder = JSONDecoder()
        let response = try decoder.decode(AuthTokenResponsePayload.self, from: data)
        let token = response.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw AuthTokenAPIError.missingTokenInResponse
        }
        return token
    }
}

public enum AuthTokenAPIError: LocalizedError, Equatable {
    case missingChallenge
    case missingSignature
    case missingPublicKey
    case invalidSecretSeed
    case signingFailed
    case missingTokenInResponse
    case invalidHTTPStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .missingChallenge:
            return "Challenge is required"
        case .missingSignature:
            return "Signature is required"
        case .missingPublicKey:
            return "Public key is required"
        case .invalidSecretSeed:
            return "Secret key must be 32 bytes"
        case .signingFailed:
            return "Failed to sign auth challenge"
        case .missingTokenInResponse:
            return "Auth response is missing token"
        case .invalidHTTPStatus(let code):
            return "Request failed with status \(code)"
        }
    }
}

private struct AuthTokenRequestPayload: Encodable {
    let challenge: String
    let signature: String
    let publicKey: String
}

private struct AuthTokenResponsePayload: Decodable {
    let token: String
}

public protocol AuthTokenFetching: Sendable {
    func fetchToken(serverURL: URL, secretSeed: Data) async throws -> String
}

public actor URLSessionAuthTokenService: AuthTokenFetching {
    public init() {}

    public func fetchToken(serverURL: URL, secretSeed: Data) async throws -> String {
        guard secretSeed.count == 32 else {
            throw AuthTokenAPIError.invalidSecretSeed
        }

        let signingKey: Curve25519.Signing.PrivateKey
        do {
            signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: secretSeed)
        } catch {
            throw AuthTokenAPIError.invalidSecretSeed
        }

        let challenge = try randomBytes(count: 32)
        let signature: Data
        do {
            signature = try signingKey.signature(for: challenge)
        } catch {
            throw AuthTokenAPIError.signingFailed
        }

        let request = try AuthTokenAPI.makeTokenRequest(
            serverURL: serverURL,
            challengeBase64: challenge.base64EncodedString(),
            signatureBase64: signature.base64EncodedString(),
            publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString()
        )
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AuthTokenAPIError.invalidHTTPStatus(http.statusCode)
        }
        return try AuthTokenAPI.decodeTokenResponse(data)
    }
}

private func randomBytes(count: Int) throws -> Data {
    var bytes = [UInt8](repeating: 0, count: count)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard status == errSecSuccess else {
        throw AuthTokenAPIError.signingFailed
    }
    return Data(bytes)
}
