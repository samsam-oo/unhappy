import Foundation

public protocol AccountSecretStoring: Sendable {
    func loadSecretBase64URL() async -> String
    func setSecretBase64URL(_ value: String) async
}

public actor UserDefaultsAccountSecretStore: AccountSecretStoring {
    private let accountSecretKey: String

    public init(
        accountSecretKey: String = "unhappy.native.account.secret"
    ) {
        self.accountSecretKey = accountSecretKey
    }

    public func loadSecretBase64URL() async -> String {
        UserDefaults.standard.string(forKey: accountSecretKey) ?? ""
    }

    public func setSecretBase64URL(_ value: String) async {
        UserDefaults.standard.set(value, forKey: accountSecretKey)
    }
}
