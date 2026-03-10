import Foundation
import CoreKit

enum SessionTranscriptEntryRole: String, Equatable, Sendable {
    case user
    case agent
    case system

    var badgeTitle: String {
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

enum SessionTranscriptEntryKind: String, Equatable, Sendable {
    case text
    case thinking
    case toolCall
    case toolResult
    case event
    case raw
}

struct SessionTranscriptEntry: Identifiable, Equatable, Sendable {
    let id: String
    let role: SessionTranscriptEntryRole
    let kind: SessionTranscriptEntryKind
    let title: String?
    let body: String
    let attachmentDataURL: String?
    let toolUseID: String?
    let sourceType: String?
    let toolName: String?
    let isSidechain: Bool
    let threadID: String?

    init(
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

struct SessionTranscriptMessagePresentation: Equatable, Sendable {
    let messageID: String
    let sequenceText: String
    let createdAt: TimeInterval
    let createdAtText: String
    let entries: [SessionTranscriptEntry]
}

enum SessionTranscriptPresentationBuilder {
    static func make(
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

    private static func defaultTimestampFormatter(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }
}
