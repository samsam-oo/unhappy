import Foundation
import SecurityKit

public protocol AccountSecretPresenceCheckingAction: Sendable {
    func hasStoredSecret() async -> Bool
}

public actor AccountSecretPresenceUseCase: AccountSecretPresenceCheckingAction {
    private let store: any AccountSecretStoring

    public init(store: any AccountSecretStoring) {
        self.store = store
    }

    public func hasStoredSecret() async -> Bool {
        let raw = await store.loadSecretBase64URL()
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        return AccountSecretCodec.decode(normalized)?.count == 32
    }
}
