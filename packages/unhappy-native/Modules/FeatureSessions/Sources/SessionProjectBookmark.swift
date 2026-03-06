import Foundation

public struct SessionProjectBookmark: Identifiable, Equatable, Sendable {
    public let machineID: String
    public let machineDisplayName: String
    public let projectPath: String

    public init(
        machineID: String,
        machineDisplayName: String,
        projectPath: String
    ) {
        self.machineID = machineID
        self.machineDisplayName = machineDisplayName
        self.projectPath = projectPath
    }

    public var id: String {
        "\(machineID)|\(projectPath)"
    }
}
