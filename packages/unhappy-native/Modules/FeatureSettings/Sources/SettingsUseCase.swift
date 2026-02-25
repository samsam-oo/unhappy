import Foundation
import CoreKit

public enum AppLanguageOption: String, CaseIterable, Sendable {
    case system
    case english
    case korean

    public var label: String {
        switch self {
        case .system:
            return "System Default"
        case .english:
            return "English"
        case .korean:
            return "Korean"
        }
    }
}

public enum AppAppearanceOption: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var label: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}

public enum AppVoiceLanguageOption: String, CaseIterable, Sendable {
    case system
    case english
    case korean

    public var label: String {
        switch self {
        case .system:
            return "System Default"
        case .english:
            return "English"
        case .korean:
            return "Korean"
        }
    }
}

public struct AppSettingsSnapshot: Sendable, Equatable {
    public let serverURLString: String
    public let apiToken: String
    public let appLanguage: AppLanguageOption
    public let appearance: AppAppearanceOption
    public let experimentsEnabled: Bool
    public let hideInactiveSessions: Bool
    public let useEnhancedSessionWizard: Bool
    public let voiceEnabled: Bool
    public let voiceLanguage: AppVoiceLanguageOption

    public init(
        serverURLString: String,
        apiToken: String,
        appLanguage: AppLanguageOption = .system,
        appearance: AppAppearanceOption = .system,
        experimentsEnabled: Bool = false,
        hideInactiveSessions: Bool = false,
        useEnhancedSessionWizard: Bool = false,
        voiceEnabled: Bool = false,
        voiceLanguage: AppVoiceLanguageOption = .system
    ) {
        self.serverURLString = serverURLString
        self.apiToken = apiToken
        self.appLanguage = appLanguage
        self.appearance = appearance
        self.experimentsEnabled = experimentsEnabled
        self.hideInactiveSessions = hideInactiveSessions
        self.useEnhancedSessionWizard = useEnhancedSessionWizard
        self.voiceEnabled = voiceEnabled
        self.voiceLanguage = voiceLanguage
    }
}

public protocol SettingsManaging: Sendable {
    func loadSettings() async -> AppSettingsSnapshot
    func persistSettings(
        serverURLString: String,
        apiToken: String,
        appLanguage: AppLanguageOption,
        appearance: AppAppearanceOption,
        experimentsEnabled: Bool,
        hideInactiveSessions: Bool,
        useEnhancedSessionWizard: Bool,
        voiceEnabled: Bool,
        voiceLanguage: AppVoiceLanguageOption
    ) async
}

public actor SettingsUseCase: SettingsManaging {
    private let store: any AppSettingsStore

    public init(store: any AppSettingsStore) {
        self.store = store
    }

    public func loadSettings() async -> AppSettingsSnapshot {
        let appLanguage = AppLanguageOption(rawValue: await store.appLanguageCode()) ?? .system
        let appearance = AppAppearanceOption(rawValue: await store.appearanceMode()) ?? .system
        let voiceLanguage = AppVoiceLanguageOption(rawValue: await store.voiceLanguageCode()) ?? .system
        return AppSettingsSnapshot(
            serverURLString: await store.serverURLString(),
            apiToken: await store.apiToken(),
            appLanguage: appLanguage,
            appearance: appearance,
            experimentsEnabled: await store.experimentsEnabled(),
            hideInactiveSessions: await store.hideInactiveSessions(),
            useEnhancedSessionWizard: await store.useEnhancedSessionWizard(),
            voiceEnabled: await store.voiceEnabled(),
            voiceLanguage: voiceLanguage
        )
    }

    public func persistSettings(
        serverURLString: String,
        apiToken: String,
        appLanguage: AppLanguageOption,
        appearance: AppAppearanceOption,
        experimentsEnabled: Bool,
        hideInactiveSessions: Bool,
        useEnhancedSessionWizard: Bool,
        voiceEnabled: Bool,
        voiceLanguage: AppVoiceLanguageOption
    ) async {
        await store.setServerURLString(serverURLString)
        await store.setAPIToken(apiToken)
        await store.setAppLanguageCode(appLanguage.rawValue)
        await store.setAppearanceMode(appearance.rawValue)
        await store.setExperimentsEnabled(experimentsEnabled)
        await store.setHideInactiveSessions(hideInactiveSessions)
        await store.setUseEnhancedSessionWizard(useEnhancedSessionWizard)
        await store.setVoiceEnabled(voiceEnabled)
        await store.setVoiceLanguageCode(voiceLanguage.rawValue)
    }
}
