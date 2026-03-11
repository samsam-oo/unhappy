import Foundation
import SecurityKit

public protocol AccountSecretStoring: Sendable {
    func loadSecretBase64URL() async -> String
    func setSecretBase64URL(_ value: String) async
}

public actor UserDefaultsAccountSecretStore: AccountSecretStoring {
    private let accountSecretKey: String
    private let defaults: UserDefaults

    public init(
        accountSecretKey: String = "unhappy.native.account.secret",
        defaults: UserDefaults = .standard
    ) {
        self.accountSecretKey = accountSecretKey
        self.defaults = defaults
    }

    public func loadSecretBase64URL() async -> String {
        defaults.string(forKey: accountSecretKey) ?? ""
    }

    public func setSecretBase64URL(_ value: String) async {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let decoded = AccountSecretCodec.decode(normalized), decoded.count == 32 {
            defaults.set(Base64URLCodec.encode(decoded), forKey: accountSecretKey)
            return
        }
        defaults.set(normalized, forKey: accountSecretKey)
    }
}
