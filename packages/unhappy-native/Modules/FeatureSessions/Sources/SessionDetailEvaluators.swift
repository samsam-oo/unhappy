import Foundation

enum SessionApprovalStateEvaluator {
    static func hasPendingApprovalRequest(
        agentState: [String: Any],
        metadata: [String: Any]
    ) -> Bool {
        let sources = [agentState, metadata]

        if let explicit = SessionPayloadValueResolver.firstBool(
            in: sources,
            keys: [
                "requiresUserApproval",
                "needsApproval",
                "approvalRequired",
                "approvalPending",
                "permissionPending",
                "waitingApproval",
                "awaitingApproval",
            ]
        ) {
            return explicit
        }

        if SessionPayloadValueResolver.hasNonEmptyArray(
            in: sources,
            keys: [
                "pendingPermissions",
                "approvalRequests",
                "permissionRequests",
                "pendingApprovalRequests",
            ]
        ) {
            return true
        }

        if SessionPayloadValueResolver.hasNonEmptyDictionary(
            in: sources,
            keys: [
                "requests",
                "pendingRequests",
                "approvalRequestMap",
                "permissionRequestMap",
            ]
        ) {
            return true
        }

        if let status = SessionPayloadValueResolver.firstString(
            in: sources,
            keys: ["status", "state", "phase"]
        )?.lowercased(),
           status.contains("approval") || status.contains("permission") {
            return true
        }

        return false
    }
}

enum SessionTranscriptLiveStatusEvaluator {
    static func latestAgentThinkingEntry(
        in presentations: [SessionTranscriptMessagePresentation]
    ) -> SessionTranscriptEntry? {
        for presentation in presentations.reversed() {
            for entry in presentation.entries.reversed() {
                guard entry.role == .agent else { continue }
                if entry.kind == .thinking {
                    return entry
                }
                return nil
            }
        }
        return nil
    }

    static func latestAgentLiveStatusText(
        in presentations: [SessionTranscriptMessagePresentation]
    ) -> String? {
        for presentation in presentations.reversed() {
            for entry in presentation.entries.reversed() {
                guard entry.role == .agent else { continue }
                if entry.kind == .thinking {
                    let body = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
                    return body.isEmpty ? "Thinking…" : body
                }
                if entry.kind == .text {
                    return nil
                }
                if let status = liveStatusText(from: entry) {
                    return status
                }
                return nil
            }
        }
        return nil
    }

    static func hasOutstandingAgentToolCalls(
        in presentations: [SessionTranscriptMessagePresentation]
    ) -> Bool {
        var outstandingToolUseIDs: Set<String> = []
        var anonymousOutstandingCalls = 0

        for presentation in presentations {
            for entry in presentation.entries where entry.role == .agent {
                switch entry.kind {
                case .toolCall:
                    if let toolUseID = normalizedToolUseID(entry.toolUseID) {
                        outstandingToolUseIDs.insert(toolUseID)
                    } else {
                        anonymousOutstandingCalls += 1
                    }
                case .toolResult:
                    if let toolUseID = normalizedToolUseID(entry.toolUseID) {
                        outstandingToolUseIDs.remove(toolUseID)
                    } else if anonymousOutstandingCalls > 0 {
                        anonymousOutstandingCalls -= 1
                    }
                default:
                    continue
                }
            }
        }

        return !outstandingToolUseIDs.isEmpty || anonymousOutstandingCalls > 0
    }

    private static func liveStatusText(from entry: SessionTranscriptEntry) -> String? {
        guard entry.kind == .toolCall || entry.kind == .raw || entry.kind == .event else {
            return nil
        }

        let title = (entry.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = title.lowercased()
        let normalizedBody = body.lowercased()
        let statusKeywords = [
            "planning",
            "explored",
            "summarizing",
            "finalizing",
            "calling",
            "crafting",
            "loading",
            "retry",
            "updating",
            "thinking",
            "image #",
        ]
        let isStatusLike = statusKeywords.contains {
            normalizedTitle.contains($0) || normalizedBody.contains($0)
        }
        guard isStatusLike else { return nil }

        if !title.isEmpty {
            return title
        }
        guard !body.isEmpty else { return nil }
        if body.count > 120 {
            return String(body.prefix(120)) + "…"
        }
        return body
    }

    private static func normalizedToolUseID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum SessionTranscriptProcessing {
    private struct FlattenedTranscriptEntry {
        let messageID: String
        let sequenceText: String
        let createdAt: TimeInterval
        let createdAtText: String
        var entry: SessionTranscriptEntry
    }

    static func coalesceStreamingEntries(
        in presentations: [SessionTranscriptMessagePresentation]
    ) -> [SessionTranscriptMessagePresentation] {
        var flattened: [FlattenedTranscriptEntry] = []
        flattened.reserveCapacity(
            presentations.reduce(into: 0) { partialResult, presentation in
                partialResult += presentation.entries.count
            }
        )
        var openStreamIndexByToolUseID: [String: Int] = [:]

        for presentation in presentations {
            for entry in presentation.entries {
                if isStreamingReferenceEntry(entry) {
                    if let toolUseID = normalizedToolUseID(entry.toolUseID),
                       let existingIndex = openStreamIndexByToolUseID[toolUseID],
                       flattened.indices.contains(existingIndex) {
                        let existing = flattened[existingIndex].entry
                        let mergedBody = mergeStreamChunk(existing: existing.body, chunk: entry.body)
                        if mergedBody != existing.body {
                            flattened[existingIndex].entry = SessionTranscriptEntry(
                                id: existing.id,
                                role: existing.role,
                                kind: existing.kind,
                                title: existing.title,
                                body: mergedBody,
                                toolUseID: existing.toolUseID,
                                sourceType: existing.sourceType,
                                toolName: existing.toolName,
                                isSidechain: existing.isSidechain,
                                threadID: existing.threadID
                            )
                        }
                        continue
                    }

                    let appendedIndex = flattened.count
                    flattened.append(
                        FlattenedTranscriptEntry(
                            messageID: presentation.messageID,
                            sequenceText: presentation.sequenceText,
                            createdAt: presentation.createdAt,
                            createdAtText: presentation.createdAtText,
                            entry: entry
                        )
                    )
                    if let toolUseID = normalizedToolUseID(entry.toolUseID) {
                        openStreamIndexByToolUseID[toolUseID] = appendedIndex
                    }
                    continue
                }

                if entry.kind == .toolResult,
                   let toolUseID = normalizedToolUseID(entry.toolUseID) {
                    openStreamIndexByToolUseID.removeValue(forKey: toolUseID)
                }

                flattened.append(
                    FlattenedTranscriptEntry(
                        messageID: presentation.messageID,
                        sequenceText: presentation.sequenceText,
                        createdAt: presentation.createdAt,
                        createdAtText: presentation.createdAtText,
                        entry: entry
                    )
                )
            }
        }

        flattened = coalesceCommandExecutionEntries(in: flattened)

        var coalesced: [SessionTranscriptMessagePresentation] = []
        coalesced.reserveCapacity(presentations.count)

        for flattenedEntry in flattened {
            if let last = coalesced.last,
               last.messageID == flattenedEntry.messageID {
                var combinedEntries = last.entries
                combinedEntries.append(flattenedEntry.entry)
                coalesced[coalesced.count - 1] = SessionTranscriptMessagePresentation(
                    messageID: last.messageID,
                    sequenceText: last.sequenceText,
                    createdAt: last.createdAt,
                    createdAtText: last.createdAtText,
                    entries: combinedEntries
                )
                continue
            }

            coalesced.append(
                SessionTranscriptMessagePresentation(
                    messageID: flattenedEntry.messageID,
                    sequenceText: flattenedEntry.sequenceText,
                    createdAt: flattenedEntry.createdAt,
                    createdAtText: flattenedEntry.createdAtText,
                    entries: [flattenedEntry.entry]
                )
            )
        }

        return coalesced
    }

    static func filterReasoningEntries(
        in presentations: [SessionTranscriptMessagePresentation],
        showReasoningDetails: Bool
    ) -> [SessionTranscriptMessagePresentation] {
        guard !showReasoningDetails else { return presentations }

        let reasoningToolUseIDs = collectReasoningToolUseIDs(in: presentations)
        var filteredPresentations: [SessionTranscriptMessagePresentation] = []
        filteredPresentations.reserveCapacity(presentations.count)

        for presentation in presentations {
            var keptEntries: [SessionTranscriptEntry] = []
            keptEntries.reserveCapacity(presentation.entries.count)

            for entry in presentation.entries {
                let normalizedToolName = entry.toolName?.lowercased()
                let normalizedSourceType = entry.sourceType?.lowercased()
                let toolUseID = normalizedToolUseID(entry.toolUseID)
                let isReasoningTool = isReasoningToolName(normalizedToolName)
                let isReasoningStream = toolUseID.map { reasoningToolUseIDs.contains($0) } ?? false
                let shouldHideReasoningEntry =
                    entry.kind == .thinking ||
                    normalizedSourceType == "reasoning" ||
                    isReasoningTool ||
                    isReasoningStream

                if shouldHideReasoningEntry {
                    continue
                }

                keptEntries.append(entry)
            }

            guard !keptEntries.isEmpty else { continue }
            if keptEntries == presentation.entries {
                filteredPresentations.append(presentation)
            } else {
                filteredPresentations.append(
                    SessionTranscriptMessagePresentation(
                        messageID: presentation.messageID,
                        sequenceText: presentation.sequenceText,
                        createdAt: presentation.createdAt,
                        createdAtText: presentation.createdAtText,
                        entries: keptEntries
                    )
                )
            }
        }

        return filteredPresentations
    }

    private static func isStreamingReferenceEntry(_ entry: SessionTranscriptEntry) -> Bool {
        guard entry.kind == .raw else { return false }
        guard let sourceType = entry.sourceType?.lowercased() else { return false }
        return sourceType == "terminal-output" || sourceType == "tool-stream"
    }

    private static func mergeStreamChunk(existing: String, chunk: String) -> String {
        SessionStreamingOutputMerger.merge(existing: existing, chunk: chunk)
    }

    private static func coalesceCommandExecutionEntries(
        in flattened: [FlattenedTranscriptEntry]
    ) -> [FlattenedTranscriptEntry] {
        var result: [FlattenedTranscriptEntry] = []
        result.reserveCapacity(flattened.count)
        var openCommandIndexByToolUseID: [String: Int] = [:]

        for flattenedEntry in flattened {
            let entry = flattenedEntry.entry

            if isStreamingReferenceEntry(entry),
               let toolUseID = normalizedToolUseID(entry.toolUseID),
               let existingIndex = openCommandIndexByToolUseID[toolUseID],
               result.indices.contains(existingIndex),
               let existingPayload = commandPayloadIfApplicable(for: result[existingIndex].entry) {
                let mergedPayload = SessionTranscriptCommandExecutionPayload(
                    command: existingPayload.command,
                    cwd: existingPayload.cwd,
                    summary: existingPayload.summary,
                    logs: mergeStreamChunk(existing: existingPayload.logs ?? "", chunk: entry.body),
                    stdout: existingPayload.stdout,
                    stderr: existingPayload.stderr,
                    success: existingPayload.success,
                    exitCode: existingPayload.exitCode,
                    status: existingPayload.status,
                    durationMs: existingPayload.durationMs
                )
                result[existingIndex] = replacingEntry(
                    result[existingIndex],
                    makeCommandEntry(
                        from: result[existingIndex].entry,
                        kind: result[existingIndex].entry.kind,
                        payload: mergedPayload
                    )
                )
                continue
            }

            if entry.kind == .toolResult,
               let toolUseID = normalizedToolUseID(entry.toolUseID),
               let existingIndex = openCommandIndexByToolUseID[toolUseID],
               result.indices.contains(existingIndex),
               let existingPayload = commandPayloadIfApplicable(for: result[existingIndex].entry),
               let resultPayload = SessionTranscriptRichContentParser.commandPayload(for: entry) {
                let derivedDurationMs = resultPayload.durationMs ?? durationMs(
                    from: result[existingIndex].createdAt,
                    to: flattenedEntry.createdAt
                )
                let mergedPayload = SessionTranscriptCommandExecutionPayload(
                    command: existingPayload.command ?? resultPayload.command,
                    cwd: existingPayload.cwd ?? resultPayload.cwd,
                    summary: existingPayload.summary ?? resultPayload.summary,
                    logs: existingPayload.logs,
                    stdout: resultPayload.stdout ?? existingPayload.stdout,
                    stderr: resultPayload.stderr ?? existingPayload.stderr,
                    success: resultPayload.success ?? existingPayload.success,
                    exitCode: resultPayload.exitCode ?? existingPayload.exitCode,
                    status: resultPayload.status ?? existingPayload.status,
                    durationMs: derivedDurationMs
                )
                result[existingIndex] = replacingEntry(
                    result[existingIndex],
                    makeCommandEntry(
                        from: result[existingIndex].entry,
                        kind: .toolResult,
                        payload: mergedPayload
                    )
                )
                openCommandIndexByToolUseID.removeValue(forKey: toolUseID)
                continue
            }

            if entry.kind == .toolCall,
               let payload = commandPayloadIfApplicable(for: entry) {
                let commandEntry = replacingEntry(
                    flattenedEntry,
                    makeCommandEntry(
                        from: entry,
                        kind: .toolCall,
                        payload: payload
                    )
                )
                let appendedIndex = result.count
                result.append(commandEntry)
                if let toolUseID = normalizedToolUseID(entry.toolUseID) {
                    openCommandIndexByToolUseID[toolUseID] = appendedIndex
                }
                continue
            }

            if entry.kind == .toolResult,
               let payload = SessionTranscriptRichContentParser.commandPayload(for: entry),
               payload.command != nil {
                result.append(
                    replacingEntry(
                        flattenedEntry,
                        makeCommandEntry(
                            from: entry,
                            kind: .toolResult,
                            payload: payload
                        )
                    )
                )
                continue
            }

            result.append(flattenedEntry)
        }

        return result
    }

    private static func commandPayloadIfApplicable(
        for entry: SessionTranscriptEntry
    ) -> SessionTranscriptCommandExecutionPayload? {
        guard entry.kind == .toolCall || entry.kind == .toolResult else {
            return nil
        }
        guard isCommandToolName(entry.toolName) ||
                SessionTranscriptRichContentParser.commandPayload(for: entry) != nil else {
            return nil
        }
        return SessionTranscriptRichContentParser.commandPayload(for: entry)
    }

    private static func makeCommandEntry(
        from entry: SessionTranscriptEntry,
        kind: SessionTranscriptEntryKind,
        payload: SessionTranscriptCommandExecutionPayload
    ) -> SessionTranscriptEntry {
        SessionTranscriptEntry(
            id: entry.id,
            role: entry.role,
            kind: kind,
            title: "Ran command",
            body: SessionTranscriptRichContentParser.encodeCommandPayload(payload),
            toolUseID: entry.toolUseID,
            sourceType: entry.sourceType,
            toolName: entry.toolName,
            isSidechain: entry.isSidechain,
            threadID: entry.threadID
        )
    }

    private static func durationMs(from start: TimeInterval, to end: TimeInterval) -> Int? {
        let delta = max(0, end - start)
        guard delta > 0 else { return nil }
        return Int((delta * 1_000).rounded())
    }

    private static func replacingEntry(
        _ flattenedEntry: FlattenedTranscriptEntry,
        _ entry: SessionTranscriptEntry
    ) -> FlattenedTranscriptEntry {
        FlattenedTranscriptEntry(
            messageID: flattenedEntry.messageID,
            sequenceText: flattenedEntry.sequenceText,
            createdAt: flattenedEntry.createdAt,
            createdAtText: flattenedEntry.createdAtText,
            entry: entry
        )
    }

    private static func collectReasoningToolUseIDs(
        in presentations: [SessionTranscriptMessagePresentation]
    ) -> Set<String> {
        var ids: Set<String> = []
        for presentation in presentations {
            for entry in presentation.entries where entry.kind == .toolCall {
                guard isReasoningToolName(entry.toolName) else { continue }
                guard let toolUseID = normalizedToolUseID(entry.toolUseID) else { continue }
                ids.insert(toolUseID)
            }
        }
        return ids
    }

    private static func isReasoningToolName(_ value: String?) -> Bool {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty else {
            return false
        }
        return normalized == "codexreasoning" ||
            normalized == "geminireasoning" ||
            normalized == "think"
    }

    private static func isCommandToolName(_ value: String?) -> Bool {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty else {
            return false
        }
        return normalized == "codexbash" || normalized == "bash"
    }

    private static func normalizedToolUseID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
