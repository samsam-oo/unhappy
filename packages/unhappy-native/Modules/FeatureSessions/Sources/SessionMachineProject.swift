import Foundation
import CoreKit

public struct SessionMachineProject: Identifiable, Equatable, Sendable {
    public let machineID: String
    public let machineDisplayName: String
    public let summary: APIMachineProjectSummary

    public init(
        machineID: String,
        machineDisplayName: String,
        summary: APIMachineProjectSummary
    ) {
        self.machineID = machineID
        self.machineDisplayName = machineDisplayName
        self.summary = summary
    }

    public var id: String {
        "\(machineID)|\(summary.path)"
    }
}
