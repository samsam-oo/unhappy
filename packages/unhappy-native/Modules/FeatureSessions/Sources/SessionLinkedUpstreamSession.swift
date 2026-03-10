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
        if let date = makeFractionalFormatter().date(from: raw) {
            return date
        }
        return makeInternetFormatter().date(from: raw)
    }

    private static func makeFractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func makeInternetFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

}
