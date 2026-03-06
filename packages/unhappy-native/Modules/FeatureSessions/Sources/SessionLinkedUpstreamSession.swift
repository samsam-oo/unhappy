import Foundation
import CoreKit

public struct SessionLinkedUpstreamSession: Identifiable, Equatable, Sendable {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public let machineID: String
    public let machineDisplayName: String
    public let summary: APIUpstreamSessionSummary

    public init(
        machineID: String,
        machineDisplayName: String,
        summary: APIUpstreamSessionSummary
    ) {
        self.machineID = machineID
        self.machineDisplayName = machineDisplayName
        self.summary = summary
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
        if let date = Self.fractionalFormatter.date(from: candidate) ?? Self.fallbackFormatter.date(from: candidate) {
            return date.timeIntervalSince1970
        }
        return 0
    }
}
