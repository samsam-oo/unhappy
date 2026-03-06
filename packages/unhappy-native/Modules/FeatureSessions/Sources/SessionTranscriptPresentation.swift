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
    let toolUseID: String?
    let sourceType: String?
    let toolName: String?
    let isSidechain: Bool
    let threadID: String?
}

struct SessionTranscriptMessagePresentation: Equatable, Sendable {
    let messageID: String
    let sequenceText: String
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
            createdAtText: timestampFormatter(message.createdAt),
            entries: visibleEntries
        )
    }

    private static func defaultTimestampFormatter(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }
}
