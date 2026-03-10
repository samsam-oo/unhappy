import Foundation
import CoreKit

public struct SessionLinkedUpstreamSession: Identifiable, Equatable, Sendable {
    public let machineID: String
    public let machineDisplayName: String
    public let wrappedMachineDataEncryptionKey: String?
    public let summary: APIUpstreamSessionSummary

    public init(
        machineID: String,
        machineDisplayName: String,
        wrappedMachineDataEncryptionKey: String? = nil,
        summary: APIUpstreamSessionSummary
    ) {
        self.machineID = machineID
        self.machineDisplayName = machineDisplayName
        self.wrappedMachineDataEncryptionKey = wrappedMachineDataEncryptionKey
        self.summary = summary
    }

    init?(session: APISession) {
        let context = SessionRuntimeContext(session: session)
        guard let upstreamIdentity = context.upstreamIdentity else { return nil }
        guard let provider = context.provider else { return nil }
        guard let machineDisplayName = context.machineDisplayName, !machineDisplayName.isEmpty else {
            return nil
        }

        self.init(
            machineID: upstreamIdentity.machineID,
            machineDisplayName: machineDisplayName,
            wrappedMachineDataEncryptionKey: session.dataEncryptionKey,
            summary: APIUpstreamSessionSummary(
                id: upstreamIdentity.upstreamSessionID,
                provider: provider,
                title: SessionDisplayTitleResolver.resolvedDisplayTitle(for: session, context: context)
                    ?? SessionDisplayTitleResolver.fallbackTitle(for: session),
                cwd: context.workingDirectory,
                path: upstreamIdentity.transcriptPath,
                updatedAt: Self.iso8601Timestamp(session.updatedAt),
                createdAt: Self.iso8601Timestamp(session.createdAt),
                archived: session.archived,
                model: context.currentModelLabel,
                effort: Self.decodeReasoningEffort(context.currentEffortLabel),
                preview: session.lastMessage?.content?.payload,
                statusType: session.active ? "running" : nil
            )
        )
    }

    public var id: String {
        "\(machineID)|\(summary.provider.rawValue)|\(summary.id)"
    }

    public var title: String {
        summary.title
    }

    public var subtitle: String? {
        summary.cwd
    }

    public var sortTimestamp: TimeInterval {
        let candidate = summary.updatedAt ?? summary.createdAt
        guard let candidate else { return 0 }
        if let date = Self.parseISO8601(candidate) {
            return date.timeIntervalSince1970
        }
        return 0
    }

    private static func parseISO8601(_ raw: String) -> Date? {
        if let date = fractionalFormatter.date(from: raw) {
            return date
        }
        return internetFormatter.date(from: raw)
    }

    nonisolated(unsafe) private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let internetFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func iso8601Timestamp(_ timestamp: TimeInterval) -> String? {
        guard timestamp > 0 else { return nil }
        return fractionalFormatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    private static func decodeReasoningEffort(_ raw: String?) -> APISessionReasoningEffort? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
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
}
