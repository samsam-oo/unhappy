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

public struct AppSettingsSnapshot: Sendable, Equatable {
    public let serverURLString: String
    public let apiToken: String
    public let appLanguage: AppLanguageOption
    public let appearance: AppAppearanceOption

    public init(
        serverURLString: String,
        apiToken: String,
        appLanguage: AppLanguageOption = .system,
        appearance: AppAppearanceOption = .system
    ) {
        self.serverURLString = serverURLString
        self.apiToken = apiToken
        self.appLanguage = appLanguage
        self.appearance = appearance
    }
}

public protocol SettingsManaging: Sendable {
    func loadSettings() async -> AppSettingsSnapshot
    func persistSettings(
        serverURLString: String,
        apiToken: String,
        appLanguage: AppLanguageOption,
        appearance: AppAppearanceOption
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
        return AppSettingsSnapshot(
            serverURLString: await store.serverURLString(),
            apiToken: await store.apiToken(),
            appLanguage: appLanguage,
            appearance: appearance
        )
    }

    public func persistSettings(
        serverURLString: String,
        apiToken: String,
        appLanguage: AppLanguageOption,
        appearance: AppAppearanceOption
    ) async {
        await store.setServerURLString(serverURLString)
        await store.setAPIToken(apiToken)
        await store.setAppLanguageCode(appLanguage.rawValue)
        await store.setAppearanceMode(appearance.rawValue)
    }
}
