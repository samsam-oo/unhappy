import SwiftUI
import CoreKit
import FeatureSessionTools

extension SessionDetailView {
    var currentSessionContext: SessionRuntimeContext {
        SessionRuntimeContext(session: currentSession)
    }

    var parsedSessionFlavor: SessionComposerFlavor? {
        if let provider = currentSessionContext.provider {
            switch provider {
            case .codex:
                return .codex
            case .claude:
                return .claude
            case .gemini:
                return .gemini
            }
        }
        return nil
    }

    var parsedSessionAgent: APISessionSpawnAgent? {
        currentSessionContext.sessionAgent
    }

    var decodedSessionMetadata: [String: Any] {
        currentSessionContext.metadata
    }

    var decodedSessionAgentState: [String: Any] {
        currentSessionContext.agentState
    }

    var collabInProgressCountFromAgentState: Int {
        currentSessionContext.collabInProgressCount
    }

    var resolvedCurrentModelLabel: String? {
        currentSessionContext.currentModelLabel
    }

    var resolvedCurrentEffortLabel: String? {
        currentSessionContext.currentEffortLabel
    }

    var resolvedCurrentPermissionMode: APISessionMessagePermissionMode? {
        currentSessionContext.currentPermissionMode
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
        currentSessionContext.requiresApproval
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
}
