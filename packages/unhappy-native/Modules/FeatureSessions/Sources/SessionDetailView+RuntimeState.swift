import SwiftUI
import CoreKit
import FeatureSessionTools

extension SessionDetailView {
    var parsedSessionFlavor: SessionComposerFlavor? {
        guard let raw = SessionPayloadValueResolver.firstString(
            in: [decodedSessionMetadata, decodedSessionAgentState],
            keys: ["flavor", "agent", "provider"]
        ) else {
            return nil
        }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let flavor = SessionComposerFlavor(rawValue: normalized) {
            return flavor
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

    var parsedSessionAgent: APISessionSpawnAgent? {
        switch parsedSessionFlavor {
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

    var decodedSessionMetadata: [String: Any] {
        SessionPayloadValueResolver.decodeJSONObject(
            payload: currentSession.metadata,
            dataEncryptionKey: currentSession.dataEncryptionKey
        )
    }

    var decodedSessionAgentState: [String: Any] {
        SessionPayloadValueResolver.decodeJSONObject(
            payload: currentSession.agentState,
            dataEncryptionKey: currentSession.dataEncryptionKey
        )
    }

    var collabInProgressCountFromAgentState: Int {
        let sources = [decodedSessionAgentState, decodedSessionMetadata]
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

    var resolvedCurrentModelLabel: String? {
        SessionPayloadValueResolver.firstString(
            in: [decodedSessionAgentState, decodedSessionMetadata],
            keys: [
                "model",
                "currentModel",
                "selectedModel",
                "modelName",
            ]
        )
    }

    var resolvedCurrentEffortLabel: String? {
        guard let raw = SessionPayloadValueResolver.firstString(
            in: [decodedSessionAgentState, decodedSessionMetadata],
            keys: [
                "effort",
                "reasoningEffort",
                "reasoning_effort",
                "modelReasoningEffort",
            ]
        ) else {
            return nil
        }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    var resolvedCurrentPermissionMode: APISessionMessagePermissionMode? {
        guard let raw = SessionPayloadValueResolver.firstString(
            in: [decodedSessionAgentState, decodedSessionMetadata],
            keys: [
                "permissionMode",
                "permission_mode",
                "approvalMode",
                "approval_mode",
                "fileMode",
                "file_mode",
            ]
        ) else {
            return nil
        }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return APISessionMessagePermissionMode(rawValue: normalized)
    }

    func permissionModeDisplayLabel(for mode: APISessionMessagePermissionMode) -> String {
        switch mode {
        case .default:
            return "Default"
        case .acceptEdits:
            return "Accept Edits"
        case .bypassPermissions:
            return "Bypass"
        case .plan:
            return "Plan"
        case .passthrough:
            return "Passthrough"
        case .readOnly:
            return "Read Only"
        case .safeYolo:
            return "Safe YOLO"
        case .yolo:
            return "YOLO"
        }
    }

    func loadServerModelOptions() async {
        let loaded = await viewModel.loadSessionModelOptions(
            for: currentSession.id,
            serverURLString: serverURLString,
            token: token,
            agent: parsedSessionAgent
        ) ?? []
        let normalized = loaded.compactMap { raw -> String? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        var deduped: [String] = []
        deduped.reserveCapacity(normalized.count)
        for model in normalized where !deduped.contains(model) {
            deduped.append(model)
        }
        if !deduped.isEmpty {
            serverModelOverrideOptions = deduped
        }
    }

    func refreshTranscriptPresentationCache(
        messages: [APISessionMessage],
        dataEncryptionKey: String?
    ) {
        var nextCache: [String: CachedTranscriptPresentation] = [:]
        nextCache.reserveCapacity(messages.count)

        var nextPresentations: [SessionTranscriptMessagePresentation] = []
        nextPresentations.reserveCapacity(messages.count)

        for message in messages {
            if let cached = transcriptPresentationCache[message.id],
               cached.sourceMessage == message,
               cached.dataEncryptionKey == dataEncryptionKey {
                nextCache[message.id] = cached
                if !cached.presentation.entries.isEmpty {
                    nextPresentations.append(cached.presentation)
                }
                continue
            }

            let presentation = SessionTranscriptPresentationBuilder.make(
                from: message,
                dataEncryptionKey: dataEncryptionKey
            )
            let cached = CachedTranscriptPresentation(
                sourceMessage: message,
                dataEncryptionKey: dataEncryptionKey,
                presentation: presentation
            )
            nextCache[message.id] = cached
            if !presentation.entries.isEmpty {
                nextPresentations.append(presentation)
            }
        }

        let mergedPresentations = SessionTranscriptProcessing.coalesceStreamingEntries(
            in: nextPresentations
        )
        let visiblePresentations = SessionTranscriptProcessing.filterReasoningEntries(
            in: mergedPresentations,
            showReasoningDetails: showReasoningDetails
        )
        transcriptPresentationCache = nextCache
        if cachedVisibleTranscriptPresentations != visiblePresentations {
            cachedVisibleTranscriptPresentations = visiblePresentations
        }
    }

    func refreshTranscriptPresentationCacheForCurrentState() {
        refreshTranscriptPresentationCache(
            messages: viewModel.selectedSessionMessages,
            dataEncryptionKey: currentSession.dataEncryptionKey
        )
    }

    var visibleTranscriptPresentations: [SessionTranscriptMessagePresentation] {
        cachedVisibleTranscriptPresentations
    }

    var visibleTranscriptMessageIDs: [String] {
        visibleTranscriptPresentations.map(\.messageID)
    }

    var latestAgentThinkingEntry: SessionTranscriptEntry? {
        SessionTranscriptLiveStatusEvaluator.latestAgentThinkingEntry(
            in: visibleTranscriptPresentations
        )
    }

    var liveStatusText: String? {
        if viewModel.isLoadingSessionMessages {
            return "Loading messages…"
        }

        if let sendingMode = viewModel.sendingSteerMode(sessionID: currentSession.id) {
            if sendingMode == .queue {
                return "Queueing…"
            }
            return "Sending…"
        }

        let queuedCount = viewModel.queuedComposerMessages(for: currentSession.id).count
        if queuedCount > 0 {
            return queuedCount == 1 ? "Queued 1 message" : "Queued \(queuedCount) messages"
        }

        if hasPendingApprovalRequest {
            return "Approval needed"
        }

        if let latestAgentLiveStatusText {
            if shouldShowAgentLiveStatus {
                return latestAgentLiveStatusText
            }
        }

        if currentSession.active {
            return "Working…"
        }

        return nil
    }

    var hasPendingApprovalRequest: Bool {
        SessionApprovalStateEvaluator.hasPendingApprovalRequest(
            agentState: decodedSessionAgentState,
            metadata: decodedSessionMetadata
        )
    }

    var shouldShowAgentLiveStatus: Bool {
        if subAgentInProgressCount > 0 {
            return true
        }
        if latestAgentThinkingEntry != nil {
            return true
        }
        return hasOutstandingAgentToolCalls
    }

    var latestAgentLiveStatusText: String? {
        SessionTranscriptLiveStatusEvaluator.latestAgentLiveStatusText(
            in: visibleTranscriptPresentations
        )
    }

    var hasOutstandingAgentToolCalls: Bool {
        SessionTranscriptLiveStatusEvaluator.hasOutstandingAgentToolCalls(
            in: visibleTranscriptPresentations
        )
    }

    func normalizedNonNegativeInt(from value: Any?) -> Int? {
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
