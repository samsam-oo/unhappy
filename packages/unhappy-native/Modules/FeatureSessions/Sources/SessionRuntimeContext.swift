import Foundation
import CoreKit

struct SessionRuntimeContext {
    let session: APISession
    let metadata: [String: Any]
    let agentState: [String: Any]
    let upstreamIdentity: SessionUpstreamIdentity?
    let machineID: String?
    let machineDisplayName: String?
    let provider: APIUpstreamSessionProvider?
    let sessionAgent: APISessionSpawnAgent?
    let currentModelLabel: String?
    let currentEffortLabel: String?
    let currentPermissionMode: APISessionMessagePermissionMode?
    let collabInProgressCount: Int
    let requiresApproval: Bool

    init(session: APISession) {
        self.session = session
        self.metadata = SessionPayloadValueResolver.decodeJSONObject(
            payload: session.metadata,
            dataEncryptionKey: session.dataEncryptionKey
        )
        self.agentState = SessionPayloadValueResolver.decodeJSONObject(
            payload: session.agentState,
            dataEncryptionKey: session.dataEncryptionKey
        )
        self.upstreamIdentity = SessionUpstreamIdentity(session: session)
        self.machineID = SessionPayloadValueResolver.firstString(
            in: [agentState, metadata],
            keys: ["machineId", "machine_id"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.machineDisplayName =
            upstreamIdentity?.machineDisplayName
            ?? SessionMachineDisplayNameResolver.resolve(in: [metadata, agentState])
        self.provider = SessionRuntimeContext.resolveProvider(
            upstreamIdentity: upstreamIdentity,
            metadata: metadata,
            agentState: agentState
        )
        self.sessionAgent = SessionRuntimeContext.resolveSessionAgent(provider: provider)
        self.currentModelLabel = SessionPayloadValueResolver.firstString(
            in: [agentState, metadata],
            keys: [
                "model",
                "currentModel",
                "selectedModel",
                "modelName",
            ]
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.currentEffortLabel = SessionPayloadValueResolver.firstString(
            in: [agentState, metadata],
            keys: [
                "effort",
                "reasoningEffort",
                "reasoning_effort",
                "modelReasoningEffort",
            ]
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let rawPermissionMode = SessionPayloadValueResolver.firstString(
            in: [agentState, metadata],
            keys: [
                "permissionMode",
                "permission_mode",
                "approvalMode",
                "approval_mode",
                "fileMode",
                "file_mode",
            ]
        )?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            self.currentPermissionMode = APISessionMessagePermissionMode(rawValue: rawPermissionMode)
        } else {
            self.currentPermissionMode = nil
        }
        self.collabInProgressCount = SessionRuntimeContext.resolveCollabInProgressCount(
            metadata: metadata,
            agentState: agentState
        )
        self.requiresApproval = SessionApprovalStateEvaluator.hasPendingApprovalRequest(
            agentState: agentState,
            metadata: metadata
        )
    }

    var workingDirectory: String? {
        if let workingDirectory = upstreamIdentity?.workingDirectory {
            return workingDirectory
        }
        let rawDirectory = SessionPayloadValueResolver.firstString(
            in: [agentState, metadata],
            keys: [
                "cwd",
                "path",
                "directory",
                "workingDirectory",
                "workDir",
                "projectPath",
            ]
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        return SessionProjectPathCanonicalizer.canonicalPath(
            rawDirectory,
            homeDirectory: homeDirectory
        )
    }

    var upstreamSessionID: String? {
        upstreamIdentity?.upstreamSessionID
    }

    private var homeDirectory: String? {
        SessionPayloadValueResolver.firstString(
            in: [agentState, metadata],
            keys: ["homeDir", "home_dir"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolveProvider(
        upstreamIdentity: SessionUpstreamIdentity?,
        metadata: [String: Any],
        agentState: [String: Any]
    ) -> APIUpstreamSessionProvider? {
        if let provider = upstreamIdentity?.provider {
            return provider
        }
        guard let raw = SessionPayloadValueResolver.firstString(
            in: [metadata, agentState],
            keys: ["flavor", "agent", "provider"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }
        if let provider = APIUpstreamSessionProvider(rawValue: raw) {
            return provider
        }
        if raw.contains("claude") {
            return .claude
        }
        if raw.contains("gemini") {
            return .gemini
        }
        if raw.contains("codex") || raw.contains("openai") || raw.contains("gpt") {
            return .codex
        }
        return nil
    }

    private static func resolveSessionAgent(
        provider: APIUpstreamSessionProvider?
    ) -> APISessionSpawnAgent? {
        switch provider {
        case .codex:
            return .codex
        case .claude:
            return .claude
        case .gemini:
            return .gemini
        case .none:
            return nil
        }
    }

    private static func resolveCollabInProgressCount(
        metadata: [String: Any],
        agentState: [String: Any]
    ) -> Int {
        let sources = [agentState, metadata]
        guard let collabState = SessionPayloadValueResolver.firstDictionary(
            in: sources,
            keys: [
                "collab",
                "collaboration",
                "multiAgent",
                "multi_agent",
            ]
        ) else {
            return 0
        }

        let activeCountKeys = [
            "activeCount",
            "active_count",
            "inProgressCount",
            "in_progress_count",
            "runningCount",
            "running_count",
            "count",
        ]
        for key in activeCountKeys {
            if let activeCount = normalizedNonNegativeInt(from: collabState[key]), activeCount > 0 {
                return activeCount
            }
        }

        let state = SessionPayloadValueResolver.firstString(
            in: [collabState],
            keys: ["state", "status", "phase"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if state == "in_progress" || state == "inprogress" || state == "running" {
            return 1
        }
        return 0
    }

    private static func normalizedNonNegativeInt(from value: Any?) -> Int? {
        if let intValue = value as? Int {
            return max(0, intValue)
        }
        if let number = value as? NSNumber {
            return max(0, number.intValue)
        }
        if let string = value as? String,
           let parsed = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return max(0, parsed)
        }
        return nil
    }
}
