import Foundation
import CoreKit

public struct NewSessionModelOption: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let description: String?
    public let isDefault: Bool
    public let upgradeBadge: String?

    public init(
        id: String,
        displayName: String,
        description: String?,
        isDefault: Bool,
        upgradeBadge: String?
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.isDefault = isDefault
        self.upgradeBadge = upgradeBadge
    }

    public init(id: String) {
        self.init(
            id: id,
            displayName: id,
            description: nil,
            isDefault: false,
            upgradeBadge: nil
        )
    }

    public var menuLabel: String {
        if isDefault {
            return "\(displayName) (Default)"
        }
        if let upgradeBadge, !upgradeBadge.isEmpty {
            return "\(displayName) (\(upgradeBadge.capitalized))"
        }
        return displayName
    }

    public static func fromCapabilities(_ capabilities: APIMachineAgentCapabilities) -> [NewSessionModelOption] {
        let preferred = capabilities.modelCapabilities
            .filter { $0.hidden != true }
            .compactMap { capability -> NewSessionModelOption? in
                let normalizedID = capability.id.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedID.isEmpty else { return nil }
                let displayName = capability.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
                return NewSessionModelOption(
                    id: normalizedID,
                    displayName: (displayName?.isEmpty == false ? displayName! : normalizedID),
                    description: capability.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                    isDefault: capability.isDefault == true,
                    upgradeBadge: capability.upgrade?.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }

        if !preferred.isEmpty {
            return preferred
        }

        return capabilities.models.map { NewSessionModelOption(id: $0) }
    }
}
