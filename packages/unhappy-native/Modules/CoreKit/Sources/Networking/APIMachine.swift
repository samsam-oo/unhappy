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

    private enum CodingKeys: String, CodingKey {
        case id
        case seq
        case active
        case activeAt
        case createdAt
        case updatedAt
        case metadataVersion
        case metadata
        case daemonStateVersion
        case daemonState
        case dataEncryptionKey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        seq = container.decodeFlexibleIntIfPresent(forKey: .seq)
        active = (try? container.decode(Bool.self, forKey: .active)) ?? false
        activeAt = container.decodeFlexibleTimeIntervalIfPresent(forKey: .activeAt) ?? 0
        createdAt = container.decodeFlexibleTimeIntervalIfPresent(forKey: .createdAt) ?? 0
        updatedAt = container.decodeFlexibleTimeIntervalIfPresent(forKey: .updatedAt) ?? 0
        metadataVersion = container.decodeFlexibleIntIfPresent(forKey: .metadataVersion) ?? 0
        metadata = (try? container.decode(String.self, forKey: .metadata)) ?? ""
        daemonStateVersion = container.decodeFlexibleIntIfPresent(forKey: .daemonStateVersion) ?? 0
        daemonState = try? container.decodeIfPresent(String.self, forKey: .daemonState)
        dataEncryptionKey = try? container.decodeIfPresent(String.self, forKey: .dataEncryptionKey)
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
