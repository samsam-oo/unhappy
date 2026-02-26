import Foundation
import Security
import CoreKit
import FeatureSettings

public enum HomeAccountOnboardingError: LocalizedError, Equatable {
    case invalidServerURL
    case keyGenerationFailed
    case failed(message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Invalid server URL"
        case .keyGenerationFailed:
            return "Failed to generate account key"
        case .failed(let message):
            return message
        }
    }
}

public protocol HomeAccountOnboardingAction: Sendable {
    func createAccount(serverURLString: String) async throws -> String
}

public actor HomeAccountOnboardingUseCase: HomeAccountOnboardingAction {
    private let authTokenService: any AuthTokenFetching
    private let secretStore: any AccountSecretStoring

    public init(
        authTokenService: any AuthTokenFetching,
        secretStore: any AccountSecretStoring
    ) {
        self.authTokenService = authTokenService
        self.secretStore = secretStore
    }

    public func createAccount(serverURLString: String) async throws -> String {
        let serverURL = try parseServerURL(serverURLString)
        let secretSeed = try randomBytes(count: 32)

        do {
            let token = try await authTokenService.fetchToken(
                serverURL: serverURL,
                secretSeed: secretSeed
            )
            await secretStore.setSecretBase64URL(encodeBase64URL(secretSeed))
            return token
        } catch let error as AuthTokenAPIError {
            throw HomeAccountOnboardingError.failed(message: error.localizedDescription)
        } catch {
            throw HomeAccountOnboardingError.failed(message: error.localizedDescription)
        }
    }

    private func parseServerURL(_ raw: String) throws -> URL {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalized.isEmpty,
            let url = URL(string: normalized),
            url.scheme != nil,
            url.host != nil
        else {
            throw HomeAccountOnboardingError.invalidServerURL
        }
        return url
    }
}

private func randomBytes(count: Int) throws -> Data {
    var bytes = [UInt8](repeating: 0, count: count)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard status == errSecSuccess else {
        throw HomeAccountOnboardingError.keyGenerationFailed
    }
    return Data(bytes)
}

private func encodeBase64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
