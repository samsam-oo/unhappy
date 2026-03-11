import Foundation

public enum SessionTranscriptProcessing {
    private struct FlattenedTranscriptEntry {
        let messageID: String
        let sequenceText: String
        let createdAt: TimeInterval
        let createdAtText: String
        var entry: SessionTranscriptEntry
    }

    public static func coalesceStreamingEntries(
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

    public static func filterReasoningEntries(
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
        var attachedToolIndexByToolUseID: [String: Int] = [:]

        for flattenedEntry in flattened {
            let entry = flattenedEntry.entry

            if isStreamingReferenceEntry(entry),
               let existingIndex = matchingOpenCommandIndex(
                    for: entry,
                    in: result,
                    openCommandIndexByToolUseID: openCommandIndexByToolUseID,
                    attachedToolIndexByToolUseID: attachedToolIndexByToolUseID
               ),
               result.indices.contains(existingIndex),
               let existingPayload = commandPayloadIfApplicable(for: result[existingIndex].entry) {
                let mergedPayload = SessionTranscriptCommandExecutionPayload(
                    command: existingPayload.command,
                    cwd: existingPayload.cwd,
                    summary: existingPayload.summary,
                    logs: mergeStreamChunk(existing: existingPayload.logs ?? "", chunk: entry.body),
                    stdout: existingPayload.stdout,
                    stderr: existingPayload.stderr,
                    sessionID: existingPayload.sessionID,
                    success: existingPayload.success,
                    exitCode: existingPayload.exitCode,
                    status: existingPayload.status,
                    durationMs: existingPayload.durationMs,
                    actions: existingPayload.actions,
                    supplementalEntries: existingPayload.supplementalEntries
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
               let existingIndex = matchingOpenCommandIndex(
                    for: entry,
                    in: result,
                    openCommandIndexByToolUseID: openCommandIndexByToolUseID,
                    attachedToolIndexByToolUseID: attachedToolIndexByToolUseID
               ),
               result.indices.contains(existingIndex),
               let existingPayload = commandPayloadIfApplicable(for: result[existingIndex].entry) {
                let normalizedToolName = entry.toolName?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if normalizedToolName == "write_stdin" {
                    let mergedPayload = SessionTranscriptCommandExecutionPayload(
                        command: existingPayload.command,
                        cwd: existingPayload.cwd,
                        summary: existingPayload.summary,
                        logs: existingPayload.logs,
                        stdout: existingPayload.stdout,
                        stderr: existingPayload.stderr,
                        sessionID: existingPayload.sessionID,
                        success: existingPayload.success,
                        exitCode: existingPayload.exitCode,
                        status: existingPayload.status,
                        durationMs: existingPayload.durationMs,
                        actions: existingPayload.actions,
                        supplementalEntries: appendSupplementalEntry(
                            existingPayload.supplementalEntries,
                            kind: .toolResult,
                            title: "write_stdin",
                            body: entry.body,
                            entryID: entry.id
                        )
                    )
                    result[existingIndex] = replacingEntry(
                        result[existingIndex],
                        makeCommandEntry(
                            from: result[existingIndex].entry,
                            kind: result[existingIndex].entry.kind,
                            payload: mergedPayload
                        )
                    )
                    if let toolUseID = normalizedToolUseID(entry.toolUseID) {
                        attachedToolIndexByToolUseID.removeValue(forKey: toolUseID)
                    }
                    continue
                }

                let resultPayload = SessionTranscriptRichContentParser.commandPayload(for: entry)
                let inferredSuccess = inferCommandResultSuccess(from: entry.body)
                let inferredStatus = inferCommandResultStatus(
                    from: entry.body,
                    fallbackSuccess: inferredSuccess
                )
                let keepsCommandOpen = shouldKeepCommandOpen(
                    toolName: normalizedToolName,
                    existingPayload: existingPayload,
                    resultPayload: resultPayload
                )
                let derivedDurationMs = resultPayload?.durationMs ?? durationMs(
                    from: result[existingIndex].createdAt,
                    to: flattenedEntry.createdAt
                )
                let mergedPayload = SessionTranscriptCommandExecutionPayload(
                    command: existingPayload.command ?? resultPayload?.command,
                    cwd: existingPayload.cwd ?? resultPayload?.cwd,
                    summary: existingPayload.summary ?? resultPayload?.summary,
                    logs: existingPayload.logs,
                    stdout: resultPayload?.stdout ?? existingPayload.stdout,
                    stderr: resultPayload?.stderr ?? existingPayload.stderr,
                    sessionID: resultPayload?.sessionID ?? existingPayload.sessionID,
                    success: keepsCommandOpen
                        ? existingPayload.success
                        : resultPayload?.success ?? existingPayload.success ?? inferredSuccess,
                    exitCode: resultPayload?.exitCode ?? existingPayload.exitCode,
                    status: keepsCommandOpen
                        ? (existingPayload.status ?? resultPayload?.status ?? "running")
                        : (resultPayload?.status ?? existingPayload.status ?? inferredStatus),
                    durationMs: derivedDurationMs,
                    actions: resultPayload?.actions ?? existingPayload.actions,
                    supplementalEntries: appendSupplementalEntry(
                        existingPayload.supplementalEntries,
                        kind: .toolResult,
                        title: entry.title ?? "Tool result",
                        body: entry.body,
                        entryID: entry.id
                    )
                )
                result[existingIndex] = replacingEntry(
                    result[existingIndex],
                    makeCommandEntry(
                        from: result[existingIndex].entry,
                        kind: keepsCommandOpen ? result[existingIndex].entry.kind : .toolResult,
                        payload: mergedPayload
                    )
                )
                if keepsCommandOpen == false {
                    if let toolUseID = normalizedToolUseID(entry.toolUseID) {
                        openCommandIndexByToolUseID.removeValue(forKey: toolUseID)
                    } else {
                        removeOpenCommandIndex(existingIndex, openCommandIndexByToolUseID: &openCommandIndexByToolUseID)
                    }
                    removeAttachedToolIndex(existingIndex, attachedToolIndexByToolUseID: &attachedToolIndexByToolUseID)
                }
                continue
            }

            if entry.kind == .toolCall,
               let normalizedToolName = entry.toolName?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased(),
               normalizedToolName == "write_stdin",
               let existingIndex = matchingOpenCommandIndex(
                    for: entry,
                    in: result,
                    openCommandIndexByToolUseID: openCommandIndexByToolUseID,
                    attachedToolIndexByToolUseID: attachedToolIndexByToolUseID
               ),
               result.indices.contains(existingIndex),
               let existingPayload = commandPayloadIfApplicable(for: result[existingIndex].entry) {
                let mergedPayload = SessionTranscriptCommandExecutionPayload(
                    command: existingPayload.command,
                    cwd: existingPayload.cwd,
                    summary: existingPayload.summary,
                    logs: existingPayload.logs,
                    stdout: existingPayload.stdout,
                    stderr: existingPayload.stderr,
                    sessionID: existingPayload.sessionID,
                    success: existingPayload.success,
                    exitCode: existingPayload.exitCode,
                    status: existingPayload.status,
                    durationMs: existingPayload.durationMs,
                    actions: existingPayload.actions,
                    supplementalEntries: appendSupplementalEntry(
                        existingPayload.supplementalEntries,
                        kind: .stdin,
                        title: "write_stdin",
                        body: entry.body,
                        entryID: entry.id
                    )
                )
                result[existingIndex] = replacingEntry(
                    result[existingIndex],
                    makeCommandEntry(
                        from: result[existingIndex].entry,
                        kind: result[existingIndex].entry.kind,
                        payload: mergedPayload
                    )
                )
                if let toolUseID = normalizedToolUseID(entry.toolUseID) {
                    attachedToolIndexByToolUseID[toolUseID] = existingIndex
                }
                continue
            }

            if isCommandTerminalEvent(entry) {
                finalizeOpenCommands(
                    in: &result,
                    openCommandIndexByToolUseID: &openCommandIndexByToolUseID,
                    attachedToolIndexByToolUseID: &attachedToolIndexByToolUseID,
                    status: entry.sourceType?.lowercased() == "turn_aborted" ? "aborted" : "completed",
                    success: entry.sourceType?.lowercased() == "turn_aborted" ? false : true,
                    completedAt: flattenedEntry.createdAt
                )
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

        return coalesceExplorationCommandEntries(in: result)
    }

    private static func coalesceExplorationCommandEntries(
        in entries: [FlattenedTranscriptEntry]
    ) -> [FlattenedTranscriptEntry] {
        guard !entries.isEmpty else { return entries }

        var result: [FlattenedTranscriptEntry] = []
        result.reserveCapacity(entries.count)

        for entry in entries {
            guard let payload = commandPayloadIfApplicable(for: entry.entry),
                  isExplorationOnly(payload) else {
                result.append(entry)
                continue
            }

            if let last = result.last,
               let lastPayload = commandPayloadIfApplicable(for: last.entry),
               isExplorationOnly(lastPayload) {
                let mergedPayload = SessionTranscriptCommandExecutionPayload(
                    command: lastPayload.command,
                    cwd: lastPayload.cwd ?? payload.cwd,
                    summary: explorationSummary(for: lastPayload.actions + payload.actions),
                    logs: nil,
                    stdout: nil,
                    stderr: nil,
                    sessionID: lastPayload.sessionID ?? payload.sessionID,
                    success: payload.success ?? lastPayload.success,
                    exitCode: payload.exitCode ?? lastPayload.exitCode,
                    status: payload.status ?? lastPayload.status,
                    durationMs: payload.durationMs ?? lastPayload.durationMs,
                    actions: deduplicatedExplorationActions(lastPayload.actions + payload.actions),
                    supplementalEntries: lastPayload.supplementalEntries + payload.supplementalEntries
                )
                result[result.count - 1] = replacingEntry(
                    last,
                    makeCommandEntry(
                        from: last.entry,
                        kind: entry.entry.kind == .toolResult ? .toolResult : last.entry.kind,
                        payload: mergedPayload
                    )
                )
                continue
            }

            result.append(entry)
        }

        return result
    }

    private static func isExplorationOnly(_ payload: SessionTranscriptCommandExecutionPayload) -> Bool {
        guard !payload.actions.isEmpty else { return false }
        guard payload.displayedLogs?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
            return false
        }
        guard payload.supplementalEntries.isEmpty else { return false }
        let explorationKinds = Set([
            SessionTranscriptCommandExecutionPayload.Action.Kind.list,
            .read,
            .search,
        ])
        return payload.actions.allSatisfy { explorationKinds.contains($0.kind) }
    }

    private static func deduplicatedExplorationActions(
        _ actions: [SessionTranscriptCommandExecutionPayload.Action]
    ) -> [SessionTranscriptCommandExecutionPayload.Action] {
        var seen: Set<String> = []
        var result: [SessionTranscriptCommandExecutionPayload.Action] = []
        for action in actions {
            let key = "\(action.kind.rawValue)|\(action.detail)"
            if seen.insert(key).inserted {
                result.append(action)
            }
        }
        return result
    }

    private static func explorationSummary(
        for actions: [SessionTranscriptCommandExecutionPayload.Action]
    ) -> String? {
        let fileCount = actions.filter { $0.kind != .search }.count
        let searchCount = actions.filter { $0.kind == .search }.count
        var parts: [String] = []
        if fileCount > 0 {
            parts.append("\(fileCount) \(fileCount == 1 ? "file" : "files")")
        }
        if searchCount > 0 {
            parts.append("\(searchCount) \(searchCount == 1 ? "search" : "searches")")
        }
        guard !parts.isEmpty else { return nil }
        return "Explored " + parts.joined(separator: ", ")
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

    private static func matchingOpenCommandIndex(
        for entry: SessionTranscriptEntry,
        in result: [FlattenedTranscriptEntry],
        openCommandIndexByToolUseID: [String: Int],
        attachedToolIndexByToolUseID: [String: Int]
    ) -> Int? {
        if let toolUseID = normalizedToolUseID(entry.toolUseID),
           let existingIndex = openCommandIndexByToolUseID[toolUseID] {
            return existingIndex
        }
        if let toolUseID = normalizedToolUseID(entry.toolUseID),
           let existingIndex = attachedToolIndexByToolUseID[toolUseID] {
            return existingIndex
        }
        if let sessionID = sessionID(for: entry) {
            let matchingIndices = Array(Set(openCommandIndexByToolUseID.values))
                .filter { index in
                    guard result.indices.contains(index),
                          let payload = commandPayloadIfApplicable(for: result[index].entry) else {
                        return false
                    }
                    return payload.sessionID == sessionID
                }
                .sorted()
            if matchingIndices.count == 1 {
                return matchingIndices[0]
            }
        }
        guard openCommandIndexByToolUseID.count == 1 else { return nil }
        return openCommandIndexByToolUseID.values.first
    }

    private static func removeOpenCommandIndex(
        _ index: Int,
        openCommandIndexByToolUseID: inout [String: Int]
    ) {
        for (key, value) in openCommandIndexByToolUseID where value == index {
            openCommandIndexByToolUseID.removeValue(forKey: key)
        }
    }

    private static func isCommandTerminalEvent(_ entry: SessionTranscriptEntry) -> Bool {
        guard entry.role == .system || entry.role == .agent else { return false }
        let sourceType = entry.sourceType?.lowercased()
        return sourceType == "task_complete" || sourceType == "turn_aborted"
    }

    private static func finalizeOpenCommands(
        in result: inout [FlattenedTranscriptEntry],
        openCommandIndexByToolUseID: inout [String: Int],
        attachedToolIndexByToolUseID: inout [String: Int],
        status: String,
        success: Bool,
        completedAt: TimeInterval
    ) {
        let indices = Array(Set(openCommandIndexByToolUseID.values)).sorted()
        guard indices.count == 1 else { return }
        for index in indices where result.indices.contains(index) {
            guard let existingPayload = commandPayloadIfApplicable(for: result[index].entry) else {
                continue
            }
            let mergedPayload = SessionTranscriptCommandExecutionPayload(
                command: existingPayload.command,
                cwd: existingPayload.cwd,
                summary: existingPayload.summary,
                logs: existingPayload.logs,
                stdout: existingPayload.stdout,
                stderr: existingPayload.stderr,
                sessionID: existingPayload.sessionID,
                success: existingPayload.success ?? success,
                exitCode: existingPayload.exitCode,
                status: existingPayload.status ?? status,
                durationMs: existingPayload.durationMs ?? durationMs(from: result[index].createdAt, to: completedAt),
                actions: existingPayload.actions,
                supplementalEntries: existingPayload.supplementalEntries
            )
            result[index] = replacingEntry(
                result[index],
                makeCommandEntry(
                    from: result[index].entry,
                    kind: .toolResult,
                    payload: mergedPayload
                )
            )
        }
        openCommandIndexByToolUseID.removeAll()
        attachedToolIndexByToolUseID.removeAll()
    }

    private static func removeAttachedToolIndex(
        _ index: Int,
        attachedToolIndexByToolUseID: inout [String: Int]
    ) {
        for (key, value) in attachedToolIndexByToolUseID where value == index {
            attachedToolIndexByToolUseID.removeValue(forKey: key)
        }
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
        return normalized == "codexbash" ||
            normalized == "bash" ||
            normalized == "exec_command"
    }

    private static func normalizedToolUseID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func appendSupplementalEntry(
        _ existing: [SessionTranscriptCommandExecutionPayload.SupplementalEntry],
        kind: SessionTranscriptCommandExecutionPayload.SupplementalEntry.Kind,
        title: String,
        body: String,
        entryID: String
    ) -> [SessionTranscriptCommandExecutionPayload.SupplementalEntry] {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return existing }
        if existing.contains(where: { $0.id == entryID || ($0.kind == kind && $0.body == trimmedBody) }) {
            return existing
        }
        return existing + [
            .init(id: entryID, kind: kind, title: title, body: trimmedBody)
        ]
    }

    private static func inferCommandResultSuccess(from rawBody: String) -> Bool? {
        let normalized = rawBody.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        if normalized.contains("failed") || normalized.contains("rejected") || normalized.contains("error") {
            return false
        }
        return true
    }

    private static func inferCommandResultStatus(
        from rawBody: String,
        fallbackSuccess: Bool?
    ) -> String? {
        if let fallbackSuccess {
            return fallbackSuccess ? "completed" : "failed"
        }
        return nil
    }

    private static func sessionID(for entry: SessionTranscriptEntry) -> String? {
        if let payloadSessionID = SessionTranscriptRichContentParser.commandPayload(for: entry)?.sessionID {
            return payloadSessionID
        }
        guard let data = entry.body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return SessionTranscriptPresentationBuilder.normalizedText(object["session_id"]) ??
            SessionTranscriptPresentationBuilder.normalizedText(object["sessionId"])
    }

    private static func shouldKeepCommandOpen(
        toolName: String?,
        existingPayload: SessionTranscriptCommandExecutionPayload,
        resultPayload: SessionTranscriptCommandExecutionPayload?
    ) -> Bool {
        let normalizedToolName = toolName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalizedToolName == "exec_command" ||
                normalizedToolName == "codexbash" ||
                normalizedToolName == "bash" else {
            return false
        }
        guard (resultPayload?.sessionID ?? existingPayload.sessionID) != nil else {
            return false
        }
        if resultPayload?.exitCode != nil || resultPayload?.success == false {
            return false
        }
        if let normalizedStatus = resultPayload?.status?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           normalizedStatus.contains("complete") ||
            normalizedStatus.contains("success") ||
            normalizedStatus.contains("done") ||
            normalizedStatus.contains("fail") ||
            normalizedStatus.contains("error") ||
            normalizedStatus.contains("abort") {
            return false
        }
        return true
    }
}
