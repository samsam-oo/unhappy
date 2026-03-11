import Foundation

public enum MachineDisplayNameCache {
    private static let defaultsKey = "unhappy.native.machine.display-name-cache"

    public static func cachedDisplayName(
        for machineID: String,
        defaults: UserDefaults = .standard
    ) -> String? {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else { return nil }
        guard let values = defaults.dictionary(forKey: defaultsKey) as? [String: String] else {
            return nil
        }
        let cached = values[normalizedMachineID]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cached, !cached.isEmpty else { return nil }
        return cached
    }

    public static func storeDisplayName(
        _ displayName: String,
        for machineID: String,
        defaults: UserDefaults = .standard
    ) {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty, !normalizedDisplayName.isEmpty else { return }
        var values = (defaults.dictionary(forKey: defaultsKey) as? [String: String]) ?? [:]
        values[normalizedMachineID] = normalizedDisplayName
        defaults.set(values, forKey: defaultsKey)
    }
}
