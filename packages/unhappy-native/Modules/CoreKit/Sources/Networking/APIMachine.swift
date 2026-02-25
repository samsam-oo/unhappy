import Foundation

public struct APIMachine: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let seq: Int?
    public let active: Bool
    public let activeAt: TimeInterval
    public let createdAt: TimeInterval
    public let updatedAt: TimeInterval
    public let metadataVersion: Int
    public let metadata: String
    public let daemonStateVersion: Int
    public let daemonState: String?
    public let dataEncryptionKey: String?

    public init(
        id: String,
        seq: Int? = nil,
        active: Bool,
        activeAt: TimeInterval,
        createdAt: TimeInterval,
        updatedAt: TimeInterval,
        metadataVersion: Int,
        metadata: String,
        daemonStateVersion: Int,
        daemonState: String?,
        dataEncryptionKey: String?
    ) {
        self.id = id
        self.seq = seq
        self.active = active
        self.activeAt = activeAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadataVersion = metadataVersion
        self.metadata = metadata
        self.daemonStateVersion = daemonStateVersion
        self.daemonState = daemonState
        self.dataEncryptionKey = dataEncryptionKey
    }
}

public struct APIMachineCommandResult: Decodable, Equatable, Sendable {
    public let success: Bool
    public let message: String
    public let error: String?

    public init(success: Bool, message: String, error: String?) {
        self.success = success
        self.message = message
        self.error = error
    }
}
