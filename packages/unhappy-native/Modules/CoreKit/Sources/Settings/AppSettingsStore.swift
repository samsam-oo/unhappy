import Foundation

public protocol AppSettingsStore: Sendable {
    func serverURLString() async -> String
    func apiToken() async -> String
    func setServerURLString(_ value: String) async
    func setAPIToken(_ value: String) async
}

public actor UserDefaultsAppSettingsStore: AppSettingsStore {
    private let defaults: UserDefaults
    private let serverURLKey: String
    private let apiTokenKey: String
    private let defaultServerURL: String

    public init(
        defaults: UserDefaults = .standard,
        serverURLKey: String = "unhappy.native.serverURL",
        apiTokenKey: String = "unhappy.native.apiToken",
        defaultServerURL: String = "https://api.unhappy.im"
    ) {
        self.defaults = defaults
        self.serverURLKey = serverURLKey
        self.apiTokenKey = apiTokenKey
        self.defaultServerURL = defaultServerURL
    }

    public func serverURLString() async -> String {
        let saved = defaults.string(forKey: serverURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let saved, !saved.isEmpty else {
            return defaultServerURL
        }
        return saved
    }

    public func apiToken() async -> String {
        defaults.string(forKey: apiTokenKey) ?? ""
    }

    public func setServerURLString(_ value: String) async {
        defaults.set(value, forKey: serverURLKey)
    }

    public func setAPIToken(_ value: String) async {
        defaults.set(value, forKey: apiTokenKey)
    }
}
