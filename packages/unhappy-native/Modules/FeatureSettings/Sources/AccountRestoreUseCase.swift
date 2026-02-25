import Foundation
import CoreKit

public enum AccountRestoreError: LocalizedError, Equatable {
    case missingAccountSecret
    case invalidAccountSecret
    case invalidServerURL
    case failed(message: String)

    public var errorDescription: String? {
        switch self {
        case .missingAccountSecret:
            return "Account secret key is required"
        case .invalidAccountSecret:
            return "Invalid account secret key"
        case .invalidServerURL:
            return "Invalid server URL"
        case .failed(let message):
            return message
        }
    }
}

public protocol AccountTokenRestoringAction: Sendable {
    func restoreToken(
        serverURLString: String,
        accountSecretRaw: String
    ) async throws -> String
}

public actor AccountRestoreUseCase: AccountTokenRestoringAction {
    private let authTokenService: any AuthTokenFetching

    public init(authTokenService: any AuthTokenFetching) {
        self.authTokenService = authTokenService
    }

    public func restoreToken(
        serverURLString: String,
        accountSecretRaw: String
    ) async throws -> String {
        let normalizedSecret = accountSecretRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSecret.isEmpty else {
            throw AccountRestoreError.missingAccountSecret
        }
        guard let secretSeed = AccountSecretCodec.decode(normalizedSecret), secretSeed.count == 32 else {
            throw AccountRestoreError.invalidAccountSecret
        }

        let serverURL = try parseServerURL(serverURLString)
        do {
            return try await authTokenService.fetchToken(serverURL: serverURL, secretSeed: secretSeed)
        } catch let error as AuthTokenAPIError {
            throw AccountRestoreError.failed(message: error.localizedDescription)
        } catch {
            throw AccountRestoreError.failed(message: error.localizedDescription)
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
            throw AccountRestoreError.invalidServerURL
        }
        return url
    }
}
