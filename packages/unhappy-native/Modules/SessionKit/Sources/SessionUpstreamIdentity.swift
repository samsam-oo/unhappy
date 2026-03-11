import Foundation
import CoreKit

public struct SessionUpstreamIdentity: Equatable, Sendable {
    public let machineID: String
    public let provider: APIUpstreamSessionProvider
    public let upstreamSessionID: String
    public let workingDirectory: String?
    public let transcriptPath: String?
    public let machineDisplayName: String?

    public var key: String {
        "\(machineID)|\(provider.rawValue)|\(upstreamSessionID)"
    }

    public init?(
        session: APISession
    ) {
        let metadata = SessionPayloadValueResolver.decodeJSONObject(
            payload: session.metadata,
            dataEncryptionKey: session.dataEncryptionKey
        )
        let agentState = SessionPayloadValueResolver.decodeJSONObject(
            payload: session.agentState,
            dataEncryptionKey: session.dataEncryptionKey
        )

        guard let provider = Self.resolveProvider(in: [agentState, metadata]) else {
            return nil
        }
        guard let machineID = Self.resolveRequiredString(
            in: [agentState, metadata],
            keys: ["machineId", "machine_id"]
        ) else {
            return nil
        }
        guard let upstreamSessionID = Self.resolveRequiredString(
            in: [agentState, metadata],
            keys: [
                "agentSessionId",
                "agent_session_id",
                "upstreamSessionId",
                "upstream_session_id",
            ]
        ) else {
            return nil
        }

        let homeDirectory = Self.resolveOptionalString(
            in: [agentState, metadata],
            keys: ["homeDir", "home_dir"]
        )

        self.machineID = machineID
        self.provider = provider
        self.upstreamSessionID = upstreamSessionID
        self.workingDirectory = SessionProjectPathCanonicalizer.canonicalPath(
            Self.resolveOptionalString(
                in: [agentState, metadata],
                keys: [
                    "cwd",
                    "path",
                    "directory",
                    "workingDirectory",
                    "workDir",
                    "projectPath",
                ]
            ),
            homeDirectory: homeDirectory
        )
        self.transcriptPath = Self.resolveOptionalString(
            in: [agentState, metadata],
            keys: [
                "agentTranscriptPath",
                "agent_transcript_path",
                "resumeFile",
                "resume_file",
            ]
        )
        self.machineDisplayName = SessionMachineDisplayNameResolver.resolve(in: [metadata, agentState])
    }

    private static func resolveProvider(in objects: [[String: Any]]) -> APIUpstreamSessionProvider? {
        guard let raw = resolveOptionalString(
            in: objects,
            keys: ["flavor", "agent", "provider"]
        ) else {
            return nil
        }
        let normalized = raw.lowercased()
        if let exact = APIUpstreamSessionProvider(rawValue: normalized) {
            return exact
        }
        if normalized.contains("claude") {
            return .claude
        }
        if normalized.contains("gemini") {
            return .gemini
        }
        if normalized.contains("codex") || normalized.contains("openai") || normalized.contains("gpt") {
            return .codex
        }
        return nil
    }

    private static func resolveRequiredString(in objects: [[String: Any]], keys: [String]) -> String? {
        resolveOptionalString(in: objects, keys: keys)
    }

    private static func resolveOptionalString(in objects: [[String: Any]], keys: [String]) -> String? {
        guard let value = SessionPayloadValueResolver.firstString(in: objects, keys: keys) else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
