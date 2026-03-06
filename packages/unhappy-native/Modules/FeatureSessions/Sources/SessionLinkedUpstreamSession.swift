import Foundation
import CoreKit

public struct SessionLinkedUpstreamSession: Identifiable, Equatable, Sendable {
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
}
