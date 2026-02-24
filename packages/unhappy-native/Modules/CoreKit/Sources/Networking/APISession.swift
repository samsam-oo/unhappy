import Foundation

public struct APISession: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let active: Bool
    public let activeAt: TimeInterval
    public let createdAt: TimeInterval
    public let updatedAt: TimeInterval
    public let metadataVersion: Int
    public let metadata: String
    public let dataEncryptionKey: String?
    public let lastMessage: APIMessage?

    public init(
        id: String,
        active: Bool,
        activeAt: TimeInterval,
        createdAt: TimeInterval,
        updatedAt: TimeInterval,
        metadataVersion: Int,
        metadata: String,
        dataEncryptionKey: String?,
        lastMessage: APIMessage?
    ) {
        self.id = id
        self.active = active
        self.activeAt = activeAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadataVersion = metadataVersion
        self.metadata = metadata
        self.dataEncryptionKey = dataEncryptionKey
        self.lastMessage = lastMessage
    }
}

public struct APIMessage: Decodable, Equatable, Sendable {
    public let id: String
    public let seq: Int
    public let content: APIEncryptedMessageContent?
    public let createdAt: TimeInterval

    public init(id: String, seq: Int, content: APIEncryptedMessageContent?, createdAt: TimeInterval) {
        self.id = id
        self.seq = seq
        self.content = content
        self.createdAt = createdAt
    }
}

public struct APISessionMessage: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let seq: Int
    public let localId: String?
    public let content: APIEncryptedMessageContent?
    public let createdAt: TimeInterval
    public let updatedAt: TimeInterval

    public init(
        id: String,
        seq: Int,
        localId: String?,
        content: APIEncryptedMessageContent?,
        createdAt: TimeInterval,
        updatedAt: TimeInterval
    ) {
        self.id = id
        self.seq = seq
        self.localId = localId
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct APIEncryptedMessageContent: Decodable, Equatable, Sendable {
    public let t: String
    public let c: String

    public init(t: String, c: String) {
        self.t = t
        self.c = c
    }
}
