import Foundation

public struct APISession: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String?
    public let seq: Int?
    public let active: Bool
    public let activeAt: TimeInterval
    public let createdAt: TimeInterval
    public let updatedAt: TimeInterval
    public let metadataVersion: Int
    public let metadata: String
    public let agentState: String?
    public let agentStateVersion: Int?
    public let dataEncryptionKey: String?
    public let lastMessage: APIMessage?

    public init(
        id: String,
        displayName: String? = nil,
        seq: Int? = nil,
        active: Bool,
        activeAt: TimeInterval,
        createdAt: TimeInterval,
        updatedAt: TimeInterval,
        metadataVersion: Int,
        metadata: String,
        agentState: String? = nil,
        agentStateVersion: Int? = nil,
        dataEncryptionKey: String?,
        lastMessage: APIMessage?
    ) {
        self.id = id
        self.displayName = displayName
        self.seq = seq
        self.active = active
        self.activeAt = activeAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadataVersion = metadataVersion
        self.metadata = metadata
        self.agentState = agentState
        self.agentStateVersion = agentStateVersion
        self.dataEncryptionKey = dataEncryptionKey
        self.lastMessage = lastMessage
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case seq
        case active
        case activeAt
        case createdAt
        case updatedAt
        case metadataVersion
        case metadata
        case agentState
        case agentStateVersion
        case dataEncryptionKey
        case lastMessage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        displayName = DecodingSupport.normalizeDisplayText(
            try? container.decodeIfPresent(String.self, forKey: .displayName)
        )
        seq = container.decodeFlexibleIntIfPresent(forKey: .seq)
        active = (try? container.decode(Bool.self, forKey: .active)) ?? false
        activeAt = container.decodeFlexibleTimeIntervalIfPresent(forKey: .activeAt) ?? 0
        createdAt = container.decodeFlexibleTimeIntervalIfPresent(forKey: .createdAt) ?? 0
        updatedAt = container.decodeFlexibleTimeIntervalIfPresent(forKey: .updatedAt) ?? 0
        metadataVersion = container.decodeFlexibleIntIfPresent(forKey: .metadataVersion) ?? 0
        metadata = (try? container.decode(String.self, forKey: .metadata)) ?? ""
        agentState = try? container.decodeIfPresent(String.self, forKey: .agentState)
        agentStateVersion = container.decodeFlexibleIntIfPresent(forKey: .agentStateVersion)
        dataEncryptionKey = try? container.decodeIfPresent(String.self, forKey: .dataEncryptionKey)
        lastMessage = try? container.decodeIfPresent(APIMessage.self, forKey: .lastMessage)
    }
}

public struct APISessionsPage: Decodable, Equatable, Sendable {
    public let sessions: [APISession]
    public let nextCursor: String?
    public let hasNext: Bool

    public init(sessions: [APISession], nextCursor: String?, hasNext: Bool) {
        self.sessions = sessions
        self.nextCursor = nextCursor
        self.hasNext = hasNext
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

    private enum CodingKeys: String, CodingKey {
        case id
        case seq
        case content
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        seq = container.decodeFlexibleIntIfPresent(forKey: .seq) ?? 0
        content = try? container.decodeIfPresent(APIEncryptedMessageContent.self, forKey: .content)
        createdAt = container.decodeFlexibleTimeIntervalIfPresent(forKey: .createdAt) ?? 0
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

    private enum CodingKeys: String, CodingKey {
        case id
        case seq
        case localId
        case content
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        seq = container.decodeFlexibleIntIfPresent(forKey: .seq) ?? 0
        localId = try? container.decodeIfPresent(String.self, forKey: .localId)
        content = try? container.decodeIfPresent(APIEncryptedMessageContent.self, forKey: .content)
        createdAt = container.decodeFlexibleTimeIntervalIfPresent(forKey: .createdAt) ?? 0
        updatedAt = container.decodeFlexibleTimeIntervalIfPresent(forKey: .updatedAt) ?? 0
    }
}

public struct APIEncryptedMessageContent: Decodable, Equatable, Sendable {
    public let t: String
    public let c: String

    public init(t: String, c: String) {
        self.t = t
        self.c = c
    }

    private enum CodingKeys: String, CodingKey {
        case t
        case c
        case type
        case text
        case payload
    }

    public init(from decoder: Decoder) throws {
        if let encoded = Self.decodeSingleValueString(from: decoder) {
            self = APIEncryptedMessageContent(t: "encrypted", c: encoded)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedType = Self.decodeType(from: container)
        let decodedPayload = Self.decodePayload(from: container)

        self = APIEncryptedMessageContent(t: decodedType, c: decodedPayload)
    }

    private static func decodeSingleValueString(from decoder: Decoder) -> String? {
        guard let container = try? decoder.singleValueContainer() else { return nil }
        return try? container.decode(String.self)
    }

    private static func decodeType(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> String {
        if let value = try? container.decodeIfPresent(String.self, forKey: .t) {
            return value
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: .type) {
            return value
        }
        return "encrypted"
    }

    private static func decodePayload(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> String {
        if let value = try? container.decodeIfPresent(String.self, forKey: .c) {
            return value
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: .payload) {
            return value
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: .text) {
            return value
        }
        return ""
    }
}

public struct APICodexThreadSummary: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let cwd: String?
    public let updatedAt: String?
    public let createdAt: String?
    public let archived: Bool?
    public let model: String?
    public let effort: APISessionReasoningEffort?
    public let preview: String?
    public let path: String?
    public let source: String?
    public let cliVersion: String?
    public let modelProvider: String?
    public let ephemeral: Bool?
    public let statusType: String?

    public init(
        id: String,
        name: String?,
        cwd: String?,
        updatedAt: String?,
        createdAt: String?,
        archived: Bool?,
        model: String? = nil,
        effort: APISessionReasoningEffort? = nil,
        preview: String? = nil,
        path: String? = nil,
        source: String? = nil,
        cliVersion: String? = nil,
        modelProvider: String? = nil,
        ephemeral: Bool? = nil,
        statusType: String? = nil
    ) {
        self.id = id
        self.name = name
        self.cwd = cwd
        self.updatedAt = updatedAt
        self.createdAt = createdAt
        self.archived = archived
        self.model = model
        self.effort = effort
        self.preview = preview
        self.path = path
        self.source = source
        self.cliVersion = cliVersion
        self.modelProvider = modelProvider
        self.ephemeral = ephemeral
        self.statusType = statusType
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case cwd
        case updatedAt
        case createdAt
        case archived
        case model
        case effort
        case preview
        case path
        case source
        case cliVersion
        case modelProvider
        case ephemeral
        case status
        case statusType
    }

    private struct ThreadStatus: Decodable {
        let type: String?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        name = DecodingSupport.normalizeDisplayText(
            try? container.decodeIfPresent(String.self, forKey: .name)
        )
        cwd = try? container.decodeIfPresent(String.self, forKey: .cwd)
        updatedAt = try? container.decodeIfPresent(String.self, forKey: .updatedAt)
        createdAt = try? container.decodeIfPresent(String.self, forKey: .createdAt)
        archived = try? container.decodeIfPresent(Bool.self, forKey: .archived)
        model = DecodingSupport.normalizeDisplayText(
            try? container.decodeIfPresent(String.self, forKey: .model)
        )
        effort = decodeReasoningEffort(
            try? container.decodeIfPresent(String.self, forKey: .effort)
        )
        preview = DecodingSupport.normalizeDisplayText(
            try? container.decodeIfPresent(String.self, forKey: .preview)
        )
        path = DecodingSupport.normalizeDisplayText(
            try? container.decodeIfPresent(String.self, forKey: .path)
        )
        source = DecodingSupport.normalizeDisplayText(
            try? container.decodeIfPresent(String.self, forKey: .source)
        )
        cliVersion = DecodingSupport.normalizeDisplayText(
            try? container.decodeIfPresent(String.self, forKey: .cliVersion)
        )
        modelProvider = DecodingSupport.normalizeDisplayText(
            try? container.decodeIfPresent(String.self, forKey: .modelProvider)
        )
        ephemeral = try? container.decodeIfPresent(Bool.self, forKey: .ephemeral)

        let directStatusType = DecodingSupport.normalizeDisplayText(
            try? container.decodeIfPresent(String.self, forKey: .statusType)
        )
        let nestedStatusType = DecodingSupport.normalizeDisplayText(
            try? container.decodeIfPresent(ThreadStatus.self, forKey: .status)?.type
        )
        statusType = directStatusType ?? nestedStatusType
    }
}

public struct APIClaudeSessionSummary: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let cwd: String?
    public let updatedAt: String?
    public let createdAt: String?

    public init(
        id: String,
        cwd: String?,
        updatedAt: String?,
        createdAt: String?
    ) {
        self.id = id
        self.cwd = cwd
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }
}

public struct APICodexThreadsPage: Decodable, Equatable, Sendable {
    public let threads: [APICodexThreadSummary]
    public let nextCursor: String?
    public let hasNext: Bool

    public init(threads: [APICodexThreadSummary], nextCursor: String?, hasNext: Bool) {
        self.threads = threads
        self.nextCursor = nextCursor
        self.hasNext = hasNext
    }
}

public struct APIClaudeSessionsPage: Decodable, Equatable, Sendable {
    public let sessions: [APIClaudeSessionSummary]
    public let nextCursor: String?
    public let hasNext: Bool

    public init(sessions: [APIClaudeSessionSummary], nextCursor: String?, hasNext: Bool) {
        self.sessions = sessions
        self.nextCursor = nextCursor
        self.hasNext = hasNext
    }
}

public enum APISessionSpawnAgent: String, Encodable, Sendable {
    case claude
    case codex
    case gemini
}

public enum APISessionReasoningEffort: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case max
    case xhigh
}

private func decodeReasoningEffort(_ raw: String?) -> APISessionReasoningEffort? {
    guard let raw else { return nil }
    let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized.isEmpty {
        return nil
    }
    switch normalized {
    case "low":
        return .low
    case "medium":
        return .medium
    case "high":
        return .high
    case "max":
        return .max
    case "xhigh":
        return .xhigh
    default:
        return nil
    }
}

public enum APISessionPermissionMode: String, Encodable, CaseIterable, Sendable {
    case `default`
    case acceptEdits
    case bypassPermissions
    case plan
}

public enum APISessionMessagePermissionMode: String, Codable, CaseIterable, Sendable {
    case `default`
    case acceptEdits
    case bypassPermissions
    case plan
    case passthrough
    case readOnly = "read-only"
    case safeYolo = "safe-yolo"
    case yolo
}

public enum APISessionPermissionDecision: String, Encodable, CaseIterable, Sendable {
    case approved
    case approvedForSession = "approved_for_session"
    case denied
    case abort
}

public enum APISessionSwitchTarget: String, Encodable, CaseIterable, Sendable {
    case remote
    case local
}

public enum APISessionSteerMode: String, Encodable, CaseIterable, Sendable {
    case queue
    case immediate
}

public struct APISessionSpawnResult: Decodable, Equatable, Sendable {
    public let success: Bool
    public let sessionID: String?
    public let requiresUserApproval: Bool?
    public let actionRequired: String?
    public let directory: String?
    public let error: String?

    public init(
        success: Bool,
        sessionID: String?,
        requiresUserApproval: Bool?,
        actionRequired: String?,
        directory: String?,
        error: String?
    ) {
        self.success = success
        self.sessionID = sessionID
        self.requiresUserApproval = requiresUserApproval
        self.actionRequired = actionRequired
        self.directory = directory
        self.error = error
    }

    private enum CodingKeys: String, CodingKey {
        case success
        case sessionID = "sessionId"
        case requiresUserApproval
        case actionRequired
        case directory
        case error
    }
}

public struct APISessionBashResult: Decodable, Equatable, Sendable {
    public let success: Bool
    public let stdout: String
    public let stderr: String
    public let exitCode: Int
    public let error: String?

    public init(
        success: Bool,
        stdout: String,
        stderr: String,
        exitCode: Int,
        error: String?
    ) {
        self.success = success
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.error = error
    }
}

public struct APISessionReadFileResult: Decodable, Equatable, Sendable {
    public let success: Bool
    public let content: String?
    public let error: String?

    public init(success: Bool, content: String?, error: String?) {
        self.success = success
        self.content = content
        self.error = error
    }
}

public struct APISessionWriteFileResult: Decodable, Equatable, Sendable {
    public let success: Bool
    public let hash: String?
    public let error: String?

    public init(success: Bool, hash: String?, error: String?) {
        self.success = success
        self.hash = hash
        self.error = error
    }
}

public struct APISessionDirectoryEntry: Decodable, Equatable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let type: String
    public let size: Int?
    public let modified: TimeInterval?

    public init(name: String, type: String, size: Int?, modified: TimeInterval?) {
        self.name = name
        self.type = type
        self.size = size
        self.modified = modified
    }
}

public struct APISessionListDirectoryResult: Decodable, Equatable, Sendable {
    public let success: Bool
    public let entries: [APISessionDirectoryEntry]?
    public let error: String?

    public init(success: Bool, entries: [APISessionDirectoryEntry]?, error: String?) {
        self.success = success
        self.entries = entries
        self.error = error
    }
}

public struct APISessionKillResult: Decodable, Equatable, Sendable {
    public let success: Bool
    public let message: String

    public init(success: Bool, message: String) {
        self.success = success
        self.message = message
    }
}

public struct APISessionCommandResult: Decodable, Equatable, Sendable {
    public let success: Bool
    public let error: String?

    public init(success: Bool, error: String?) {
        self.success = success
        self.error = error
    }
}

public struct APISessionSwitchResult: Decodable, Equatable, Sendable {
    public let success: Bool
    public let switched: Bool?
    public let error: String?

    public init(success: Bool, switched: Bool?, error: String?) {
        self.success = success
        self.switched = switched
        self.error = error
    }
}

public struct APISessionSendMessageResult: Decodable, Equatable, Sendable {
    public let success: Bool
    public let queueCount: Int?
    public let queuedMessages: [String]?
    public let error: String?

    public init(success: Bool, queueCount: Int?, queuedMessages: [String]?, error: String?) {
        self.success = success
        self.queueCount = queueCount
        self.queuedMessages = queuedMessages
        self.error = error
    }
}
