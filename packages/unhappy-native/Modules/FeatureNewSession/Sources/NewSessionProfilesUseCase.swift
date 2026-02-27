import Foundation
import CoreKit

public struct NewSessionProfile: Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var machineID: String?
    public var directoryPath: String
    public var agent: APISessionSpawnAgent
    public var codexResumeThreadID: String?
    public var claudeResumeSessionID: String?
    public var sessionToken: String?
    public var model: String?
    public var reasoningEffort: APISessionReasoningEffort?
    public var environmentVariablesText: String

    public init(
        id: String,
        name: String,
        machineID: String?,
        directoryPath: String,
        agent: APISessionSpawnAgent,
        codexResumeThreadID: String?,
        claudeResumeSessionID: String?,
        sessionToken: String?,
        model: String? = nil,
        reasoningEffort: APISessionReasoningEffort? = nil,
        environmentVariablesText: String
    ) {
        self.id = id
        self.name = name
        self.machineID = machineID
        self.directoryPath = directoryPath
        self.agent = agent
        self.codexResumeThreadID = codexResumeThreadID
        self.claudeResumeSessionID = claudeResumeSessionID
        self.sessionToken = sessionToken
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.environmentVariablesText = environmentVariablesText
    }
}

public protocol NewSessionProfilesStore: Sendable {
    func loadProfiles() async -> [NewSessionProfile]
    func saveProfiles(_ profiles: [NewSessionProfile]) async
}

public protocol NewSessionProfilesManaging: Sendable {
    func loadProfiles() async -> [NewSessionProfile]
    func saveProfile(_ profile: NewSessionProfile) async -> [NewSessionProfile]
    func deleteProfile(id: String) async -> [NewSessionProfile]
}

public actor UserDefaultsNewSessionProfilesStore: NewSessionProfilesStore {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "unhappy.native.newSessionProfiles"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func loadProfiles() async -> [NewSessionProfile] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([NewSessionProfileDTO].self, from: data) else {
            return []
        }
        return decoded.map(\.profile)
    }

    public func saveProfiles(_ profiles: [NewSessionProfile]) async {
        let payload = profiles.map(NewSessionProfileDTO.init(profile:))
        if let encoded = try? JSONEncoder().encode(payload) {
            defaults.set(encoded, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

public actor NewSessionProfilesUseCase: NewSessionProfilesManaging {
    private let store: any NewSessionProfilesStore
    private let maxProfiles: Int

    public init(store: any NewSessionProfilesStore, maxProfiles: Int = 20) {
        self.store = store
        self.maxProfiles = max(1, maxProfiles)
    }

    public func loadProfiles() async -> [NewSessionProfile] {
        await store.loadProfiles()
    }

    public func saveProfile(_ profile: NewSessionProfile) async -> [NewSessionProfile] {
        let normalized = normalizedProfile(profile)
        var profiles = await store.loadProfiles()
        if let index = profiles.firstIndex(where: { $0.id == normalized.id }) {
            profiles[index] = normalized
        } else {
            profiles.insert(normalized, at: 0)
        }
        if profiles.count > maxProfiles {
            profiles = Array(profiles.prefix(maxProfiles))
        }
        await store.saveProfiles(profiles)
        return profiles
    }

    public func deleteProfile(id: String) async -> [NewSessionProfile] {
        var profiles = await store.loadProfiles()
        profiles.removeAll { $0.id == id }
        await store.saveProfiles(profiles)
        return profiles
    }
}

public actor NewSessionNoopProfilesManager: NewSessionProfilesManaging {
    public init() {}

    public func loadProfiles() async -> [NewSessionProfile] { [] }
    public func saveProfile(_ profile: NewSessionProfile) async -> [NewSessionProfile] { [profile] }
    public func deleteProfile(id: String) async -> [NewSessionProfile] { [] }
}

private func normalizedProfile(_ profile: NewSessionProfile) -> NewSessionProfile {
    NewSessionProfile(
        id: profile.id.trimmingCharacters(in: .whitespacesAndNewlines),
        name: profile.name.trimmingCharacters(in: .whitespacesAndNewlines),
        machineID: normalizedOptional(profile.machineID),
        directoryPath: profile.directoryPath.trimmingCharacters(in: .whitespacesAndNewlines),
        agent: profile.agent,
        codexResumeThreadID: normalizedOptional(profile.codexResumeThreadID),
        claudeResumeSessionID: normalizedOptional(profile.claudeResumeSessionID),
        sessionToken: normalizedOptional(profile.sessionToken),
        model: normalizedOptional(profile.model),
        reasoningEffort: profile.reasoningEffort,
        environmentVariablesText: profile.environmentVariablesText
    )
}

private func normalizedOptional(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private struct NewSessionProfileDTO: Codable {
    let id: String
    let name: String
    let machineID: String?
    let directoryPath: String
    let agent: String
    let codexResumeThreadID: String?
    let claudeResumeSessionID: String?
    let sessionToken: String?
    let model: String?
    let reasoningEffort: String?
    let environmentVariablesText: String

    var profile: NewSessionProfile {
        NewSessionProfile(
            id: id,
            name: name,
            machineID: machineID,
            directoryPath: directoryPath,
            agent: APISessionSpawnAgent(rawValue: agent) ?? .claude,
            codexResumeThreadID: codexResumeThreadID,
            claudeResumeSessionID: claudeResumeSessionID,
            sessionToken: sessionToken,
            model: model,
            reasoningEffort: APISessionReasoningEffort(rawValue: reasoningEffort ?? ""),
            environmentVariablesText: environmentVariablesText
        )
    }

    init(profile: NewSessionProfile) {
        id = profile.id
        name = profile.name
        machineID = profile.machineID
        directoryPath = profile.directoryPath
        agent = profile.agent.rawValue
        codexResumeThreadID = profile.codexResumeThreadID
        claudeResumeSessionID = profile.claudeResumeSessionID
        sessionToken = profile.sessionToken
        model = profile.model
        reasoningEffort = profile.reasoningEffort?.rawValue
        environmentVariablesText = profile.environmentVariablesText
    }
}
