import Foundation
import ActivityKit

public enum UnhappySessionAgentKind: String, Codable, Hashable, Sendable {
    case codex
    case claude
    case gemini
    case unknown
}

public struct UnhappySessionsActivityAttributes: ActivityAttributes, Sendable {
    public let sessionID: String

    public init(sessionID: String) {
        self.sessionID = sessionID
    }

    public struct ContentState: Codable, Hashable, Sendable {
        public let title: String
        public let agent: UnhappySessionAgentKind
        public let directory: String
        public let statusText: String
        public let requiresApproval: Bool
        public let updatedAt: Date

        public init(
            title: String,
            agent: UnhappySessionAgentKind,
            directory: String,
            statusText: String,
            requiresApproval: Bool,
            updatedAt: Date
        ) {
            self.title = title
            self.agent = agent
            self.directory = directory
            self.statusText = statusText
            self.requiresApproval = requiresApproval
            self.updatedAt = updatedAt
        }
    }
}
