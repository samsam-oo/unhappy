import SwiftUI
import CoreKit

public struct SessionProjectPickerSheetContext: Sendable {
    public let serverURLString: String
    public let token: String
    public let defaultAgent: APISessionSpawnAgent

    public init(
        serverURLString: String,
        token: String,
        defaultAgent: APISessionSpawnAgent
    ) {
        self.serverURLString = serverURLString
        self.token = token
        self.defaultAgent = defaultAgent
    }
}

public struct SessionProjectPickerResult: Equatable, Sendable {
    public let machineID: String?
    public let directoryPath: String
    public let machineDisplayName: String?
    public let wrappedMachineDataEncryptionKey: String?

    public init(
        machineID: String?,
        directoryPath: String,
        machineDisplayName: String?,
        wrappedMachineDataEncryptionKey: String?
    ) {
        self.machineID = machineID
        self.directoryPath = directoryPath
        self.machineDisplayName = machineDisplayName
        self.wrappedMachineDataEncryptionKey = wrappedMachineDataEncryptionKey
    }
}

public typealias SessionProjectPickerSheetBuilder =
    @MainActor (SessionProjectPickerSheetContext, @escaping (SessionProjectPickerResult) -> Void) -> AnyView

public struct SessionProjectStartSheetContext: Sendable {
    public let serverURLString: String
    public let token: String
    public let defaultAgent: APISessionSpawnAgent
    public let initialMachineID: String
    public let initialDirectoryPath: String

    public init(
        serverURLString: String,
        token: String,
        defaultAgent: APISessionSpawnAgent,
        initialMachineID: String,
        initialDirectoryPath: String
    ) {
        self.serverURLString = serverURLString
        self.token = token
        self.defaultAgent = defaultAgent
        self.initialMachineID = initialMachineID
        self.initialDirectoryPath = initialDirectoryPath
    }
}

public struct SessionProjectStartResult: Equatable, Sendable {
    public let sessionID: String?
    public let transcriptPath: String?
    public let agent: APISessionSpawnAgent
    public let machineID: String?
    public let directoryPath: String
    public let model: String?

    public init(
        sessionID: String?,
        transcriptPath: String?,
        agent: APISessionSpawnAgent,
        machineID: String?,
        directoryPath: String,
        model: String?
    ) {
        self.sessionID = sessionID
        self.transcriptPath = transcriptPath
        self.agent = agent
        self.machineID = machineID
        self.directoryPath = directoryPath
        self.model = model
    }
}

public typealias SessionProjectStartSheetBuilder =
    @MainActor (SessionProjectStartSheetContext, @escaping (SessionProjectStartResult) -> Void) -> AnyView
