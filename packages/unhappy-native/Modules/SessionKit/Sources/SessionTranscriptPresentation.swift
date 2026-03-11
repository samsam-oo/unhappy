import Foundation
import CoreKit

public enum SessionTranscriptEntryRole: String, Equatable, Sendable {
    case user
    case agent
    case system

    public var badgeTitle: String {
        switch self {
        case .user:
            return "You"
        case .agent:
            return "Agent"
        case .system:
            return "System"
        }
    }
}

public enum SessionTranscriptEntryKind: String, Equatable, Sendable {
    case text
    case thinking
    case toolCall
    case toolResult
    case event
    case raw
}

public struct SessionTranscriptEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let role: SessionTranscriptEntryRole
    public let kind: SessionTranscriptEntryKind
    public let title: String?
    public let body: String
    public let attachmentDataURL: String?
    public let toolUseID: String?
    public let sourceType: String?
    public let toolName: String?
    public let isSidechain: Bool
    public let threadID: String?

    public init(
        id: String,
        role: SessionTranscriptEntryRole,
        kind: SessionTranscriptEntryKind,
        title: String?,
        body: String,
        attachmentDataURL: String? = nil,
        toolUseID: String? = nil,
        sourceType: String? = nil,
        toolName: String? = nil,
        isSidechain: Bool,
        threadID: String?
    ) {
        self.id = id
        self.role = role
        self.kind = kind
        self.title = title
        self.body = body
        self.attachmentDataURL = attachmentDataURL
        self.toolUseID = toolUseID
        self.sourceType = sourceType
        self.toolName = toolName
        self.isSidechain = isSidechain
        self.threadID = threadID
    }
}

public struct SessionTranscriptMessagePresentation: Equatable, Sendable {
    public let messageID: String
    public let sequenceText: String
    public let createdAt: TimeInterval
    public let createdAtText: String
    public let entries: [SessionTranscriptEntry]

    public init(
        messageID: String,
        sequenceText: String,
        createdAt: TimeInterval,
        createdAtText: String,
        entries: [SessionTranscriptEntry]
    ) {
        self.messageID = messageID
        self.sequenceText = sequenceText
        self.createdAt = createdAt
        self.createdAtText = createdAtText
        self.entries = entries
    }
}

public enum SessionTranscriptPresentationBuilder {
    public static func make(
        from message: APISessionMessage,
        dataEncryptionKey: String?,
        timestampFormatter: (TimeInterval) -> String = defaultTimestampFormatter
    ) -> SessionTranscriptMessagePresentation {
        let payloadString = decodePayloadString(
            content: message.content,
            dataEncryptionKey: dataEncryptionKey
        )

        let entries = parseEntries(
            payloadString: payloadString,
            messageID: message.id
        )

        let visibleEntries = entries.filter { shouldDisplay(entry: $0) }

        return SessionTranscriptMessagePresentation(
            messageID: message.id,
            sequenceText: "\(message.seq)",
            createdAt: message.createdAt,
            createdAtText: timestampFormatter(message.createdAt),
            entries: visibleEntries
        )
    }

    public static func defaultTimestampFormatter(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }
}
