import Foundation
import CoreKit

public struct NewSessionReasoningEffort: Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    public static let auto = NewSessionReasoningEffort(rawValue: "auto")
    public static let low = NewSessionReasoningEffort(rawValue: "low")
    public static let medium = NewSessionReasoningEffort(rawValue: "medium")
    public static let high = NewSessionReasoningEffort(rawValue: "high")
    public static let max = NewSessionReasoningEffort(rawValue: "max")
    public static let xhigh = NewSessionReasoningEffort(rawValue: "xhigh")

    public var displayName: String {
        switch rawValue {
        case "auto":
            return "Auto"
        case "low":
            return "Low"
        case "medium":
            return "Medium"
        case "high":
            return "High"
        case "max":
            return "Max"
        case "xhigh":
            return "XHigh"
        case "minimal":
            return "Minimal"
        case "none":
            return "None"
        default:
            return rawValue.capitalized
        }
    }

    public var apiValue: APISessionReasoningEffort? {
        switch rawValue {
        case "low":
            return .low
        case "medium":
            return .medium
        case "high":
            return .high
        case "max":
            return .max
        case "xhigh":
            return .xhigh
        default:
            return nil
        }
    }

    public init(threadEffort: APISessionReasoningEffort?) {
        if let threadEffort {
            self = NewSessionReasoningEffort(rawValue: threadEffort.rawValue)
        } else {
            self = .medium
        }
    }

    public static func fromBackend(_ raw: String) -> NewSessionReasoningEffort? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return nil }
        return NewSessionReasoningEffort(rawValue: normalized)
    }
}
