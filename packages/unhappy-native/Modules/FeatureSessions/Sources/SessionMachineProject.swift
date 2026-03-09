import Foundation
import CoreKit

public struct SessionMachineProject: Identifiable, Equatable, Sendable {
    public let machineID: String
    public let machineDisplayName: String
    public let wrappedMachineDataEncryptionKey: String?
    public let summary: APIMachineProjectSummary

    public init(
        machineID: String,
        machineDisplayName: String,
        wrappedMachineDataEncryptionKey: String? = nil,
        summary: APIMachineProjectSummary
    ) {
        self.machineID = machineID
        self.machineDisplayName = machineDisplayName
        self.wrappedMachineDataEncryptionKey = wrappedMachineDataEncryptionKey
        self.summary = summary
    }

    public var id: String {
        "\(machineID)|\(summary.path)"
    }
}
