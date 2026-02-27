import Foundation
import CoreKit

public enum SessionMessageModelOverride: Hashable, Sendable {
    case inherit
    case reset
    case set(String)
}

public enum SessionMessageEffortOverride: Hashable, Sendable {
    case inherit
    case auto
    case low
    case medium
    case high
    case max
    case xhigh

    var apiEffort: APISessionReasoningEffort? {
        switch self {
        case .inherit, .auto:
            return nil
        case .low:
            return .low
        case .medium:
            return .medium
        case .high:
            return .high
        case .max:
            return .max
        case .xhigh:
            return .xhigh
        }
    }
}
