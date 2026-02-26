import Foundation

public protocol AppSettingsStore: Sendable {
    func serverURLString() async -> String
    func apiToken() async -> String
    func appLanguageCode() async -> String
    func appearanceMode() async -> String
    func experimentsEnabled() async -> Bool
    func hideInactiveSessions() async -> Bool
    func useEnhancedSessionWizard() async -> Bool
    func voiceEnabled() async -> Bool
    func voiceLanguageCode() async -> String
    func defaultNewSessionAgent() async -> String
    func lastViewedChangelogID() async -> String
    func recentProjectPaths() async -> [String]
    func setServerURLString(_ value: String) async
    func setAPIToken(_ value: String) async
    func setAppLanguageCode(_ value: String) async
    func setAppearanceMode(_ value: String) async
    func setExperimentsEnabled(_ value: Bool) async
    func setHideInactiveSessions(_ value: Bool) async
    func setUseEnhancedSessionWizard(_ value: Bool) async
    func setVoiceEnabled(_ value: Bool) async
    func setVoiceLanguageCode(_ value: String) async
    func setDefaultNewSessionAgent(_ value: String) async
    func setLastViewedChangelogID(_ value: String) async
    func setRecentProjectPaths(_ value: [String]) async
}

public actor UserDefaultsAppSettingsStore: AppSettingsStore {
    private let defaults: UserDefaults
    private let serverURLKey: String
    private let apiTokenKey: String
    private let appLanguageKey: String
    private let appearanceModeKey: String
    private let experimentsEnabledKey: String
    private let hideInactiveSessionsKey: String
    private let useEnhancedSessionWizardKey: String
    private let voiceEnabledKey: String
    private let voiceLanguageKey: String
    private let defaultNewSessionAgentKey: String
    private let lastViewedChangelogIDKey: String
    private let recentProjectPathsKey: String
    private let defaultServerURL: String

    public init(
        defaults: UserDefaults = .standard,
        serverURLKey: String = "unhappy.native.serverURL",
        apiTokenKey: String = "unhappy.native.apiToken",
        appLanguageKey: String = "unhappy.native.appLanguage",
        appearanceModeKey: String = "unhappy.native.appearanceMode",
        experimentsEnabledKey: String = "unhappy.native.experimentsEnabled",
        hideInactiveSessionsKey: String = "unhappy.native.hideInactiveSessions",
        useEnhancedSessionWizardKey: String = "unhappy.native.useEnhancedSessionWizard",
        voiceEnabledKey: String = "unhappy.native.voiceEnabled",
        voiceLanguageKey: String = "unhappy.native.voiceLanguage",
        defaultNewSessionAgentKey: String = "unhappy.native.defaultNewSessionAgent",
        lastViewedChangelogIDKey: String = "unhappy.native.lastViewedChangelogID",
        recentProjectPathsKey: String = "unhappy.native.recentProjectPaths",
        defaultServerURL: String = "https://api.unhappy.im"
    ) {
        self.defaults = defaults
        self.serverURLKey = serverURLKey
        self.apiTokenKey = apiTokenKey
        self.appLanguageKey = appLanguageKey
        self.appearanceModeKey = appearanceModeKey
        self.experimentsEnabledKey = experimentsEnabledKey
        self.hideInactiveSessionsKey = hideInactiveSessionsKey
        self.useEnhancedSessionWizardKey = useEnhancedSessionWizardKey
        self.voiceEnabledKey = voiceEnabledKey
        self.voiceLanguageKey = voiceLanguageKey
        self.defaultNewSessionAgentKey = defaultNewSessionAgentKey
        self.lastViewedChangelogIDKey = lastViewedChangelogIDKey
        self.recentProjectPathsKey = recentProjectPathsKey
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

    public func appLanguageCode() async -> String {
        defaults.string(forKey: appLanguageKey) ?? "system"
    }

    public func appearanceMode() async -> String {
        defaults.string(forKey: appearanceModeKey) ?? "system"
    }

    public func experimentsEnabled() async -> Bool {
        defaults.bool(forKey: experimentsEnabledKey)
    }

    public func hideInactiveSessions() async -> Bool {
        defaults.bool(forKey: hideInactiveSessionsKey)
    }

    public func useEnhancedSessionWizard() async -> Bool {
        defaults.bool(forKey: useEnhancedSessionWizardKey)
    }

    public func voiceEnabled() async -> Bool {
        defaults.bool(forKey: voiceEnabledKey)
    }

    public func voiceLanguageCode() async -> String {
        defaults.string(forKey: voiceLanguageKey) ?? "system"
    }

    public func defaultNewSessionAgent() async -> String {
        defaults.string(forKey: defaultNewSessionAgentKey) ?? "claude"
    }

    public func lastViewedChangelogID() async -> String {
        defaults.string(forKey: lastViewedChangelogIDKey) ?? ""
    }

    public func recentProjectPaths() async -> [String] {
        if let data = defaults.data(forKey: recentProjectPathsKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return normalizedProjectPaths(decoded)
        }
        if let fallback = defaults.array(forKey: recentProjectPathsKey) as? [String] {
            return normalizedProjectPaths(fallback)
        }
        return []
    }

    public func setServerURLString(_ value: String) async {
        defaults.set(value, forKey: serverURLKey)
    }

    public func setAPIToken(_ value: String) async {
        defaults.set(value, forKey: apiTokenKey)
    }

    public func setAppLanguageCode(_ value: String) async {
        defaults.set(value, forKey: appLanguageKey)
    }

    public func setAppearanceMode(_ value: String) async {
        defaults.set(value, forKey: appearanceModeKey)
    }

    public func setExperimentsEnabled(_ value: Bool) async {
        defaults.set(value, forKey: experimentsEnabledKey)
    }

    public func setHideInactiveSessions(_ value: Bool) async {
        defaults.set(value, forKey: hideInactiveSessionsKey)
    }

    public func setUseEnhancedSessionWizard(_ value: Bool) async {
        defaults.set(value, forKey: useEnhancedSessionWizardKey)
    }

    public func setVoiceEnabled(_ value: Bool) async {
        defaults.set(value, forKey: voiceEnabledKey)
    }

    public func setVoiceLanguageCode(_ value: String) async {
        defaults.set(value, forKey: voiceLanguageKey)
    }

    public func setDefaultNewSessionAgent(_ value: String) async {
        defaults.set(value, forKey: defaultNewSessionAgentKey)
    }

    public func setLastViewedChangelogID(_ value: String) async {
        defaults.set(value, forKey: lastViewedChangelogIDKey)
    }

    public func setRecentProjectPaths(_ value: [String]) async {
        let normalized = normalizedProjectPaths(value)
        if let encoded = try? JSONEncoder().encode(normalized) {
            defaults.set(encoded, forKey: recentProjectPathsKey)
        } else {
            defaults.removeObject(forKey: recentProjectPathsKey)
        }
    }
}

private func normalizedProjectPaths(_ value: [String]) -> [String] {
    value.compactMap { raw in
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
