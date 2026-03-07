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

public struct ChangelogEntry: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let publishedAt: String
    public let highlights: [String]

    public init(
        id: String,
        title: String,
        publishedAt: String,
        highlights: [String]
    ) {
        self.id = id
        self.title = title
        self.publishedAt = publishedAt
        self.highlights = highlights
    }
}

public enum SettingsChangelog {
    public static let entries: [ChangelogEntry] = [
        ChangelogEntry(
            id: "2026.02.26",
            title: "Settings parity update",
            publishedAt: "Feb 26, 2026",
            highlights: [
                "Added a native changelog screen in Settings.",
                "Added unread indicator support for new changelog entries.",
                "Persisted last viewed changelog version in app settings."
            ]
        ),
        ChangelogEntry(
            id: "2026.02.21",
            title: "Account linking improvements",
            publishedAt: "Feb 21, 2026",
            highlights: [
                "Improved account link flow reliability and error handling.",
                "Refined restore paths for token and QR onboarding."
            ]
        ),
        ChangelogEntry(
            id: "2026.02.14",
            title: "Settings and machine updates",
            publishedAt: "Feb 14, 2026",
            highlights: [
                "Expanded machine management controls in Settings.",
                "Improved usage and connection settings organization."
            ]
        )
    ]

    public static var latestEntryID: String {
        entries.first?.id ?? ""
    }

    public static func hasUnread(lastViewedID: String) -> Bool {
        let latest = latestEntryID
        guard !latest.isEmpty else { return false }
        let normalizedLastViewedID = lastViewedID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLastViewedID.isEmpty else { return true }
        if normalizedLastViewedID == latest {
            return false
        }
        return latest.compare(normalizedLastViewedID, options: .numeric) == .orderedDescending
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
    public let defaultNewSessionAgent: APISessionSpawnAgent
    public let lastViewedChangelogID: String

    public init(
        serverURLString: String,
        apiToken: String,
        appLanguage: AppLanguageOption = .system,
        appearance: AppAppearanceOption = .system,
        experimentsEnabled: Bool = false,
        hideInactiveSessions: Bool = false,
        useEnhancedSessionWizard: Bool = false,
        voiceEnabled: Bool = false,
        voiceLanguage: AppVoiceLanguageOption = .system,
        defaultNewSessionAgent: APISessionSpawnAgent = .claude,
        lastViewedChangelogID: String = ""
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
        self.defaultNewSessionAgent = defaultNewSessionAgent
        self.lastViewedChangelogID = lastViewedChangelogID
    }
}

public protocol SettingsManaging: Sendable {
    func loadSettings() async -> AppSettingsSnapshot
    func persistSettings(_ snapshot: AppSettingsSnapshot) async
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
        let defaultNewSessionAgent = APISessionSpawnAgent(rawValue: await store.defaultNewSessionAgent()) ?? .claude
        return AppSettingsSnapshot(
            serverURLString: await store.serverURLString(),
            apiToken: await store.apiToken(),
            appLanguage: appLanguage,
            appearance: appearance,
            experimentsEnabled: await store.experimentsEnabled(),
            hideInactiveSessions: await store.hideInactiveSessions(),
            useEnhancedSessionWizard: await store.useEnhancedSessionWizard(),
            voiceEnabled: await store.voiceEnabled(),
            voiceLanguage: voiceLanguage,
            defaultNewSessionAgent: defaultNewSessionAgent,
            lastViewedChangelogID: await store.lastViewedChangelogID()
        )
    }

    public func persistSettings(_ snapshot: AppSettingsSnapshot) async {
        await store.setServerURLString(snapshot.serverURLString)
        await store.setAPIToken(snapshot.apiToken)
        await store.setAppLanguageCode(snapshot.appLanguage.rawValue)
        await store.setAppearanceMode(snapshot.appearance.rawValue)
        await store.setExperimentsEnabled(snapshot.experimentsEnabled)
        await store.setHideInactiveSessions(snapshot.hideInactiveSessions)
        await store.setUseEnhancedSessionWizard(snapshot.useEnhancedSessionWizard)
        await store.setVoiceEnabled(snapshot.voiceEnabled)
        await store.setVoiceLanguageCode(snapshot.voiceLanguage.rawValue)
        await store.setDefaultNewSessionAgent(snapshot.defaultNewSessionAgent.rawValue)
        await store.setLastViewedChangelogID(snapshot.lastViewedChangelogID)
    }
}
