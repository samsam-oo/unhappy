import Foundation

public enum MachineDataPlaneProtocol {
    public static let version = 1
    public static let subprotocol = "unhappy-machine-dp.v1"
    public static let pathTemplate = "/v1/machines/:machineId/data-plane"
    public static let defaultMaxChunkBytes = 262_144
    public static let defaultMaxInFlightStreams = 8
}

public enum MachineDataPlaneRole: String, Codable, Sendable {
    case native
    case daemon
}

public struct MachineDataPlaneKeyExchange: Codable, Equatable, Sendable {
    public let algorithm: String
    public let publicKey: String
    public let nonce: String

    public init(
        algorithm: String = "x25519-hkdf-sha256",
        publicKey: String,
        nonce: String
    ) {
        self.algorithm = algorithm
        self.publicKey = publicKey
        self.nonce = nonce
    }
}

public struct MachineDataPlaneSealedBody: Codable, Equatable, Sendable {
    public let algorithm: String
    public let nonce: String
    public let ciphertext: String
    public let tag: String

    public init(
        algorithm: String = "aes-256-gcm",
        nonce: String,
        ciphertext: String,
        tag: String
    ) {
        self.algorithm = algorithm
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
    }
}

public enum MachineDataPlaneOperation: String, Codable, CaseIterable, Sendable {
    case providerSpawn = "provider.spawn"
    case projectList = "project.list"
    case projectOpen = "project.open"
    case projectRemove = "project.remove"
    case codexListThreads = "codex.listThreads"
    case codexOpenThread = "codex.openThread"
    case codexListMessages = "codex.listMessages"
    case codexSendMessage = "codex.sendMessage"
    case claudeListSessions = "claude.listSessions"
    case claudeListMessages = "claude.listMessages"
    case claudeSendMessage = "claude.sendMessage"
    case geminiListSessions = "gemini.listSessions"
    case geminiListMessages = "gemini.listMessages"
    case geminiSendMessage = "gemini.sendMessage"
    case fsListDirectory = "fs.listDirectory"
    case fsGetDirectoryTree = "fs.getDirectoryTree"
    case fsReadFile = "fs.readFile"
    case fsWriteFile = "fs.writeFile"
    case execBash = "exec.bash"
    case searchRipgrep = "search.ripgrep"
    case diffDifftastic = "diff.difftastic"
}

public enum MachineDataPlaneFrameType: String, Codable, Sendable {
    case hello
    case helloAck = "hello-ack"
    case request
    case chunk
    case complete
    case error
    case ack
}

public struct MachineDataPlaneHelloFrame: Codable, Equatable, Sendable {
    public let v: Int
    public let t: MachineDataPlaneFrameType
    public let connectionID: String
    public let role: MachineDataPlaneRole
    public let keyExchange: MachineDataPlaneKeyExchange
    public let supportsChunkAck: Bool
    public let supportsResume: Bool
    public let lastAckedStreamID: String?

    enum CodingKeys: String, CodingKey {
        case v
        case t
        case connectionID = "connectionId"
        case role
        case keyExchange
        case supportsChunkAck
        case supportsResume
        case lastAckedStreamID = "lastAckedStreamId"
    }

    public init(
        connectionID: String,
        role: MachineDataPlaneRole,
        keyExchange: MachineDataPlaneKeyExchange,
        supportsChunkAck: Bool = true,
        supportsResume: Bool = true,
        lastAckedStreamID: String? = nil
    ) {
        self.v = MachineDataPlaneProtocol.version
        self.t = .hello
        self.connectionID = connectionID
        self.role = role
        self.keyExchange = keyExchange
        self.supportsChunkAck = supportsChunkAck
        self.supportsResume = supportsResume
        self.lastAckedStreamID = lastAckedStreamID
    }
}

public struct MachineDataPlaneHelloAckFrame: Codable, Equatable, Sendable {
    public let v: Int
    public let t: MachineDataPlaneFrameType
    public let connectionID: String
    public let sessionID: String
    public let keyExchange: MachineDataPlaneKeyExchange
    public let maxChunkBytes: Int
    public let maxInFlightStreams: Int
    public let idleTimeoutSeconds: Int

    enum CodingKeys: String, CodingKey {
        case v
        case t
        case connectionID = "connectionId"
        case sessionID = "sessionId"
        case keyExchange
        case maxChunkBytes
        case maxInFlightStreams
        case idleTimeoutSeconds
    }
}

public struct MachineDataPlaneRequestFrame: Codable, Equatable, Sendable {
    public let v: Int
    public let t: MachineDataPlaneFrameType
    public let streamID: String
    public let op: MachineDataPlaneOperation
    public let body: MachineDataPlaneSealedBody
    public let expectsChunks: Bool

    enum CodingKeys: String, CodingKey {
        case v
        case t
        case streamID = "streamId"
        case op
        case body
        case expectsChunks
    }

    public init(
        streamID: String,
        op: MachineDataPlaneOperation,
        body: MachineDataPlaneSealedBody,
        expectsChunks: Bool = true
    ) {
        self.v = MachineDataPlaneProtocol.version
        self.t = .request
        self.streamID = streamID
        self.op = op
        self.body = body
        self.expectsChunks = expectsChunks
    }
}

public struct MachineDataPlaneChunkFrame: Codable, Equatable, Sendable {
    public let v: Int
    public let t: MachineDataPlaneFrameType
    public let streamID: String
    public let seq: Int
    public let body: MachineDataPlaneSealedBody
    public let final: Bool

    enum CodingKeys: String, CodingKey {
        case v
        case t
        case streamID = "streamId"
        case seq
        case body
        case final
    }
}

public struct MachineDataPlaneCompleteFrame: Codable, Equatable, Sendable {
    public let v: Int
    public let t: MachineDataPlaneFrameType
    public let streamID: String
    public let seq: Int
    public let body: MachineDataPlaneSealedBody
    public let hasMore: Bool?
    public let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case v
        case t
        case streamID = "streamId"
        case seq
        case body
        case hasMore
        case nextCursor
    }
}

public struct MachineDataPlaneErrorFrame: Codable, Equatable, Sendable {
    public let v: Int
    public let t: MachineDataPlaneFrameType
    public let streamID: String
    public let code: String
    public let message: String
    public let retryable: Bool

    enum CodingKeys: String, CodingKey {
        case v
        case t
        case streamID = "streamId"
        case code
        case message
        case retryable
    }
}

public struct MachineDataPlaneAckFrame: Codable, Equatable, Sendable {
    public let v: Int
    public let t: MachineDataPlaneFrameType
    public let streamID: String
    public let seq: Int

    enum CodingKeys: String, CodingKey {
        case v
        case t
        case streamID = "streamId"
        case seq
    }

    public init(streamID: String, seq: Int) {
        self.v = MachineDataPlaneProtocol.version
        self.t = .ack
        self.streamID = streamID
        self.seq = seq
    }
}
