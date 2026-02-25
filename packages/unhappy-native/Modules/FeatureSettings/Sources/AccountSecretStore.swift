import Foundation

public protocol AccountSecretStoring: Sendable {
    func loadSecretBase64URL() async -> String
    func setSecretBase64URL(_ value: String) async
}

public actor UserDefaultsAccountSecretStore: AccountSecretStoring {
    private let defaults: UserDefaults
    private let accountSecretKey: String

    public init(
        defaults: UserDefaults = .standard,
        accountSecretKey: String = "unhappy.native.account.secret"
    ) {
        self.defaults = defaults
        self.accountSecretKey = accountSecretKey
    }

    public func loadSecretBase64URL() async -> String {
        defaults.string(forKey: accountSecretKey) ?? ""
    }

    public func setSecretBase64URL(_ value: String) async {
        defaults.set(value, forKey: accountSecretKey)
    }
}
