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

public struct APICodexThreadSummary: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let cwd: String?
    public let updatedAt: String?
    public let createdAt: String?
    public let archived: Bool?

    public init(
        id: String,
        name: String?,
        cwd: String?,
        updatedAt: String?,
        createdAt: String?,
        archived: Bool?
    ) {
        self.id = id
        self.name = name
        self.cwd = cwd
        self.updatedAt = updatedAt
        self.createdAt = createdAt
        self.archived = archived
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

public enum APISessionSpawnAgent: String, Encodable, Sendable {
    case claude
    case codex
    case gemini
}

public enum APISessionPermissionMode: String, Encodable, CaseIterable, Sendable {
    case `default`
    case acceptEdits
    case bypassPermissions
    case plan
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
