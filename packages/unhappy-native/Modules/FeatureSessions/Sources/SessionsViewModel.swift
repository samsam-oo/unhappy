import Foundation
import CoreKit

@MainActor
public final class SessionsViewModel: ObservableObject {
    private enum CachePolicy {
        static let maxCachedSessions = 4
        static let maxMessagesPerSession = 150
    }

    @Published public private(set) var sessions: [APISession] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var hasMoreSessions = false
    @Published public private(set) var isLoadingMoreSessions = false
    @Published public private(set) var selectedSessionID: String?
    @Published public private(set) var selectedSessionMessages: [APISessionMessage] = []
    @Published public private(set) var isLoadingSessionMessages = false
    @Published public private(set) var selectedSessionErrorMessage: String?
    @Published public private(set) var selectedCodexThreads: [APICodexThreadSummary] = []
    @Published public private(set) var isLoadingCodexThreads = false
    @Published public private(set) var selectedCodexThreadsErrorMessage: String?
    @Published public private(set) var selectedCodexThreadsSessionID: String?
    @Published public private(set) var codexResumeInProgressThreadID: String?
    @Published public private(set) var codexResumeStatusMessage: String?
    @Published public private(set) var codexResumeErrorMessage: String?
    @Published public private(set) var selectedClaudeSessions: [APIClaudeSessionSummary] = []
    @Published public private(set) var isLoadingClaudeSessions = false
    @Published public private(set) var selectedClaudeSessionsErrorMessage: String?
    @Published public private(set) var selectedClaudeSessionsSessionID: String?
    @Published public private(set) var claudeResumeInProgressSessionID: String?
    @Published public private(set) var claudeResumeStatusMessage: String?
    @Published public private(set) var claudeResumeErrorMessage: String?
    @Published public private(set) var deletingSessionIDs: Set<String> = []
    @Published public private(set) var renamingSessionIDs: Set<String> = []
    @Published public private(set) var sendingMessageSessionID: String?
    @Published public private(set) var sendingMessageSteerMode: APISessionSteerMode?
    @Published public private(set) var sendMessageStatusMessage: String?
    @Published public private(set) var sendMessageErrorMessage: String?
    @Published public private(set) var queuedComposerMessagesBySessionID: [String: [String]] = [:]

    private let loader: any SessionsLoading
    private let pageLoader: any SessionsPageLoading
    private let poller: any SessionsPolling
    private let messageLoader: any SessionsMessagesLoading
    private let codexThreadsLoader: (any SessionCodexThreadsLoading)?
    private let claudeSessionsLoader: (any SessionClaudeSessionsLoading)?
    private let sessionModelsLoader: (any SessionModelsLoadingAction)?
    private let spawnUseCase: (any SessionSpawningAction)?
    private let messageSender: (any SessionMessageSendingAction)?
    private let preDeleteKiller: (any SessionPreDeleteKillingAction)?
    private let deleteUseCase: any SessionDeletingAction
    private let titleUseCase: any SessionTitleUpdatingAction
    private var messagesBySessionID: [String: [APISessionMessage]] = [:]
    private var messageCacheLRU: [String] = []
    private var nextCursor: String?
    private var selectedSessionMessagesPollingTask: Task<Void, Never>?
    private var selectedSessionMessagesPollingTaskID: UUID?

    public init(
        loader: any SessionsLoading,
        pageLoader: any SessionsPageLoading,
        poller: any SessionsPolling,
        messageLoader: any SessionsMessagesLoading,
        codexThreadsLoader: (any SessionCodexThreadsLoading)? = nil,
        claudeSessionsLoader: (any SessionClaudeSessionsLoading)? = nil,
        sessionModelsLoader: (any SessionModelsLoadingAction)? = nil,
        spawnUseCase: (any SessionSpawningAction)? = nil,
        messageSender: (any SessionMessageSendingAction)? = nil,
        preDeleteKiller: (any SessionPreDeleteKillingAction)? = nil,
        deleteUseCase: any SessionDeletingAction,
        titleUseCase: any SessionTitleUpdatingAction
    ) {
        self.loader = loader
        self.pageLoader = pageLoader
        self.poller = poller
        self.messageLoader = messageLoader
        self.codexThreadsLoader = codexThreadsLoader
        self.claudeSessionsLoader = claudeSessionsLoader
        self.sessionModelsLoader = sessionModelsLoader
        self.spawnUseCase = spawnUseCase
        self.messageSender = messageSender
        self.preDeleteKiller = preDeleteKiller
        self.deleteUseCase = deleteUseCase
        self.titleUseCase = titleUseCase
    }

    public convenience init(
        service: any SessionsFetching & SessionsPagingFetching & SessionMessagesFetching & SessionDeleting & SessionTitleUpdating & SessionCodexThreadsFetching & SessionClaudeSessionsFetching & SessionSpawning
    ) {
        let loader = SessionsLoadUseCase(service: service)
        let messageSenderUseCase: (any SessionMessageSendingAction)?
        if let messagingService = service as? any SessionMessaging {
            messageSenderUseCase = SessionMessageSendUseCase(service: messagingService)
        } else {
            messageSenderUseCase = nil
        }
        let preDeleteKillUseCase: (any SessionPreDeleteKillingAction)?
        if let killingService = service as? any SessionKilling {
            preDeleteKillUseCase = SessionPreDeleteKillUseCase(service: killingService)
        } else {
            preDeleteKillUseCase = nil
        }
        self.init(
            loader: loader,
            pageLoader: SessionsPageLoadUseCase(service: service),
            poller: SessionsPollingUseCase(loader: loader),
            messageLoader: SessionMessagesLoadUseCase(service: service),
            codexThreadsLoader: SessionCodexThreadsLoadUseCase(service: service),
            claudeSessionsLoader: SessionClaudeSessionsLoadUseCase(service: service),
            sessionModelsLoader: (service as? any SessionModelsListing).map {
                SessionModelsLoadUseCase(service: $0)
            },
            spawnUseCase: SessionSpawnUseCase(service: service),
            messageSender: messageSenderUseCase,
            preDeleteKiller: preDeleteKillUseCase,
            deleteUseCase: SessionDeleteUseCase(service: service),
            titleUseCase: SessionTitleUpdateUseCase(service: service)
        )
    }

    public var multiAgentInProgress: Bool {
        if isLoading {
            return true
        }
        return sessions.contains(where: { $0.active })
    }

    public var activeSessionsCount: Int {
        sessions.filter(\.active).count
    }

    public var isResumingClaudeSession: Bool {
        claudeResumeInProgressSessionID != nil
    }

    public var isResumingCodexSession: Bool {
        codexResumeInProgressThreadID != nil
    }

    var cachedSessionMessagesCount: Int {
        messagesBySessionID.count
    }

    var isSelectedSessionMessagesPolling: Bool {
        selectedSessionMessagesPollingTask != nil
    }

    public func isDeleting(sessionID: String) -> Bool {
        deletingSessionIDs.contains(sessionID)
    }

    public func isRenaming(sessionID: String) -> Bool {
        renamingSessionIDs.contains(sessionID)
    }

    public func isSendingMessage(sessionID: String) -> Bool {
        sendingMessageSessionID == sessionID
    }

    public func sendingSteerMode(sessionID: String) -> APISessionSteerMode? {
        guard sendingMessageSessionID == sessionID else { return nil }
        return sendingMessageSteerMode
    }

    public func queuedComposerMessages(for sessionID: String) -> [String] {
        queuedComposerMessagesBySessionID[sessionID] ?? []
    }

    public func load(serverURLString: String, token: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let firstPage = try await pageLoader.loadPage(
                serverURLString: serverURLString,
                token: token,
                cursor: nil,
                limit: 50
            )
            sessions = firstPage.sessions
            refreshQueuedComposerMessagesCache(from: sessions)
            nextCursor = firstPage.nextCursor
            hasMoreSessions = firstPage.hasNext
            errorMessage = nil
        } catch {
            sessions = []
            refreshQueuedComposerMessagesCache(from: sessions)
            nextCursor = nil
            hasMoreSessions = false
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func startPolling(
        serverURLString: String,
        token: String,
        interval: Duration = .seconds(20)
    ) async {
        isLoading = true
        errorMessage = nil

        do {
            let stream = await poller.makePollingStream(
                serverURLString: serverURLString,
                token: token,
                interval: interval
            )
            for try await rows in stream {
                sessions = mergeLatestRows(rows, into: sessions)
                refreshQueuedComposerMessagesCache(from: sessions)
                errorMessage = nil
                isLoading = false
            }
        } catch is CancellationError {
            // Stream cancellation is expected when the view task is torn down.
        } catch {
            sessions = []
            refreshQueuedComposerMessagesCache(from: sessions)
            nextCursor = nil
            hasMoreSessions = false
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isLoading = false
        }
    }

    public func loadMoreSessions(serverURLString: String, token: String) async {
        guard hasMoreSessions else { return }
        guard !isLoadingMoreSessions else { return }
        guard let nextCursor else {
            hasMoreSessions = false
            return
        }

        isLoadingMoreSessions = true
        defer { isLoadingMoreSessions = false }

        do {
            let page = try await pageLoader.loadPage(
                serverURLString: serverURLString,
                token: token,
                cursor: nextCursor,
                limit: 50
            )
            sessions = mergeLatestRows(page.sessions, into: sessions)
            refreshQueuedComposerMessagesCache(from: sessions)
            self.nextCursor = page.nextCursor
            hasMoreSessions = page.hasNext
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func startSelectedSessionMessagesPolling(
        for sessionID: String,
        serverURLString: String,
        token: String,
        interval: Duration = .seconds(5)
    ) {
        stopSelectedSessionMessagesPolling()

        let taskID = UUID()
        selectedSessionMessagesPollingTaskID = taskID
        selectedSessionMessagesPollingTask = Task { [weak self] in
            guard let self else { return }
            await self.runSelectedSessionMessagesPolling(
                taskID: taskID,
                sessionID: sessionID,
                serverURLString: serverURLString,
                token: token,
                interval: interval
            )
        }
    }

    public func stopSelectedSessionMessagesPolling() {
        selectedSessionMessagesPollingTask?.cancel()
        selectedSessionMessagesPollingTask = nil
        selectedSessionMessagesPollingTaskID = nil
    }

    public func loadMessages(
        for sessionID: String,
        serverURLString: String,
        token: String,
        showsLoadingState: Bool = true,
        clearsMessagesOnFailure: Bool = true
    ) async {
        selectedSessionID = sessionID
        selectedSessionErrorMessage = nil

        if showsLoadingState {
            isLoadingSessionMessages = true
            if let cachedMessages = messagesBySessionID[sessionID] {
                setSelectedSessionMessagesIfNeeded(cachedMessages)
            } else {
                setSelectedSessionMessagesIfNeeded([])
            }
        }

        defer {
            if showsLoadingState {
                isLoadingSessionMessages = false
            }
        }

        do {
            let fetchedMessages = try await messageLoader.loadMessages(
                serverURLString: serverURLString,
                token: token,
                sessionID: sessionID
            )
            let mergedMessages = mergeFetchedMessages(fetchedMessages, for: sessionID)
            let normalizedMessages = cacheMessages(mergedMessages, for: sessionID)
            if selectedSessionID == sessionID {
                setSelectedSessionMessagesIfNeeded(normalizedMessages)
                selectedSessionErrorMessage = nil
            }
        } catch let apiError as SessionsAPIError {
            if case .invalidHTTPStatus(404) = apiError {
                sessions.removeAll { $0.id == sessionID }
                messagesBySessionID[sessionID] = nil
                messageCacheLRU.removeAll { $0 == sessionID }
                if selectedSessionID == sessionID {
                    setSelectedSessionMessagesIfNeeded([])
                    selectedSessionErrorMessage = "Session no longer exists on server."
                }
                return
            }
            if selectedSessionID == sessionID {
                if clearsMessagesOnFailure {
                    setSelectedSessionMessagesIfNeeded([])
                }
                selectedSessionErrorMessage = apiError.errorDescription ?? apiError.localizedDescription
            }
        } catch {
            if selectedSessionID == sessionID {
                if clearsMessagesOnFailure {
                    setSelectedSessionMessagesIfNeeded([])
                }
                selectedSessionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    public func loadCodexThreads(
        for sessionID: String,
        serverURLString: String,
        token: String,
        limit: Int = 20,
        cwd: String? = nil
    ) async {
        selectedCodexThreadsSessionID = sessionID
        selectedCodexThreadsErrorMessage = nil
        selectedCodexThreads = []
        isLoadingCodexThreads = true
        defer { isLoadingCodexThreads = false }

        guard let codexThreadsLoader else {
            selectedCodexThreadsErrorMessage = "Codex thread listing is unavailable in this build"
            return
        }

        do {
            let threads = try await codexThreadsLoader.loadCodexThreads(
                serverURLString: serverURLString,
                token: token,
                sessionID: sessionID,
                limit: limit,
                cwd: cwd
            )
            if selectedCodexThreadsSessionID == sessionID {
                selectedCodexThreads = threads
                selectedCodexThreadsErrorMessage = nil
            }
        } catch {
            if selectedCodexThreadsSessionID == sessionID {
                selectedCodexThreads = []
                selectedCodexThreadsErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    public func loadClaudeSessions(
        for sessionID: String,
        serverURLString: String,
        token: String,
        limit: Int = 20,
        cwd: String? = nil
    ) async {
        selectedClaudeSessionsSessionID = sessionID
        selectedClaudeSessionsErrorMessage = nil
        selectedClaudeSessions = []
        isLoadingClaudeSessions = true
        defer { isLoadingClaudeSessions = false }

        guard let claudeSessionsLoader else {
            selectedClaudeSessionsErrorMessage = "Claude session listing is unavailable in this build"
            return
        }

        do {
            let rows = try await claudeSessionsLoader.loadClaudeSessions(
                serverURLString: serverURLString,
                token: token,
                sessionID: sessionID,
                limit: limit,
                cwd: cwd
            )
            if selectedClaudeSessionsSessionID == sessionID {
                selectedClaudeSessions = rows
                selectedClaudeSessionsErrorMessage = nil
            }
        } catch {
            if selectedClaudeSessionsSessionID == sessionID {
                selectedClaudeSessions = []
                selectedClaudeSessionsErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    public func resumeCodexThread(
        from sourceSessionID: String,
        codexResumeThreadID: String,
        serverURLString: String,
        token: String,
        directory: String
    ) async {
        codexResumeInProgressThreadID = codexResumeThreadID
        codexResumeStatusMessage = nil
        codexResumeErrorMessage = nil
        defer {
            if codexResumeInProgressThreadID == codexResumeThreadID {
                codexResumeInProgressThreadID = nil
            }
        }

        guard let spawnUseCase else {
            codexResumeErrorMessage = "Thread resume is unavailable in this build"
            return
        }

        do {
            let response = try await spawnUseCase.spawnSession(
                serverURLString: serverURLString,
                token: token,
                sessionID: sourceSessionID,
                directory: directory,
                agent: .codex,
                codexResumeThreadID: codexResumeThreadID,
                claudeResumeSessionID: nil,
                approvedNewDirectoryCreation: true
            )

            if let sessionID = response.sessionID, !sessionID.isEmpty {
                codexResumeStatusMessage = "Resumed into new session \(sessionID)"
            } else {
                codexResumeStatusMessage = "Resumed Codex thread"
            }
            codexResumeErrorMessage = nil

            await load(serverURLString: serverURLString, token: token)
        } catch {
            codexResumeStatusMessage = nil
            codexResumeErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func resumeClaudeSession(
        from sourceSessionID: String,
        claudeResumeSessionID: String,
        serverURLString: String,
        token: String,
        directory: String
    ) async {
        claudeResumeInProgressSessionID = claudeResumeSessionID
        claudeResumeStatusMessage = nil
        claudeResumeErrorMessage = nil
        defer {
            if claudeResumeInProgressSessionID == claudeResumeSessionID {
                claudeResumeInProgressSessionID = nil
            }
        }

        guard let spawnUseCase else {
            claudeResumeErrorMessage = "Session resume is unavailable in this build"
            return
        }

        do {
            let response = try await spawnUseCase.spawnSession(
                serverURLString: serverURLString,
                token: token,
                sessionID: sourceSessionID,
                directory: directory,
                agent: .claude,
                codexResumeThreadID: nil,
                claudeResumeSessionID: claudeResumeSessionID,
                approvedNewDirectoryCreation: true
            )

            if let sessionID = response.sessionID, !sessionID.isEmpty {
                claudeResumeStatusMessage = "Resumed into new session \(sessionID)"
            } else {
                claudeResumeStatusMessage = "Resumed Claude session"
            }
            claudeResumeErrorMessage = nil

            await load(serverURLString: serverURLString, token: token)
        } catch {
            claudeResumeStatusMessage = nil
            claudeResumeErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func sendMessage(
        for sessionID: String,
        text: String,
        steerMode: APISessionSteerMode,
        modelOverride: SessionMessageModelOverride = .inherit,
        effortOverride: SessionMessageEffortOverride = .inherit,
        serverURLString: String,
        token: String
    ) async -> Bool {
        guard sendingMessageSessionID == nil else { return false }
        guard let messageSender else {
            sendMessageStatusMessage = nil
            sendMessageErrorMessage = "Message sender is unavailable"
            return false
        }

        sendingMessageSessionID = sessionID
        sendingMessageSteerMode = steerMode
        sendMessageStatusMessage = nil
        sendMessageErrorMessage = nil
        defer {
            sendingMessageSessionID = nil
            sendingMessageSteerMode = nil
        }

        do {
            let result = try await messageSender.sendMessage(
                serverURLString: serverURLString,
                token: token,
                sessionID: sessionID,
                text: text,
                steerMode: steerMode,
                modelOverride: modelOverride,
                effortOverride: effortOverride
            )
            sendMessageStatusMessage = nil
            sendMessageErrorMessage = nil
            applyQueuedComposerSnapshot(
                for: sessionID,
                steerMode: steerMode,
                sentText: text,
                response: result
            )
            appendOptimisticUserMessageIfPossible(for: sessionID, text: text)
            return true
        } catch {
            sendMessageStatusMessage = nil
            sendMessageErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    public func loadSessionModelOptions(
        for sessionID: String,
        serverURLString: String,
        token: String,
        agent: APISessionSpawnAgent?
    ) async -> [String]? {
        guard let sessionModelsLoader else { return nil }
        do {
            let capabilities = try await sessionModelsLoader.loadSessionModels(
                serverURLString: serverURLString,
                token: token,
                sessionID: sessionID,
                agent: agent
            )
            return capabilities.models
        } catch {
            return nil
        }
    }

    public func deleteSession(sessionID: String, serverURLString: String, token: String) async {
        deletingSessionIDs.insert(sessionID)
        defer { deletingSessionIDs.remove(sessionID) }

        var killFailureMessage: String?
        if let preDeleteKiller {
            do {
                try await preDeleteKiller.killSession(
                    serverURLString: serverURLString,
                    token: token,
                    sessionID: sessionID
                )
            } catch {
                killFailureMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }

        do {
            try await deleteUseCase.deleteSession(
                serverURLString: serverURLString,
                token: token,
                sessionID: sessionID
            )

            sessions.removeAll { $0.id == sessionID }
            queuedComposerMessagesBySessionID[sessionID] = nil
            messagesBySessionID[sessionID] = nil
            if selectedSessionID == sessionID {
                stopSelectedSessionMessagesPolling()
                selectedSessionID = nil
                setSelectedSessionMessagesIfNeeded([])
                selectedSessionErrorMessage = nil
            }
            messageCacheLRU.removeAll { $0 == sessionID }
            if let killFailureMessage {
                errorMessage = "Deleted session record, but failed to terminate local session process: \(killFailureMessage)"
            } else {
                errorMessage = nil
            }
        } catch {
            let deleteFailureMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if let killFailureMessage {
                errorMessage = "Failed to terminate local session process: \(killFailureMessage). Session record delete also failed: \(deleteFailureMessage)"
            } else {
                errorMessage = deleteFailureMessage
            }
        }
    }

    public func clearDetailSelectionIfNeeded(sessionID: String) {
        guard selectedSessionID == sessionID else { return }
        stopSelectedSessionMessagesPolling()
        selectedSessionID = nil
        setSelectedSessionMessagesIfNeeded([])
        selectedSessionErrorMessage = nil
        if selectedCodexThreadsSessionID == sessionID {
            selectedCodexThreadsSessionID = nil
            selectedCodexThreads = []
            selectedCodexThreadsErrorMessage = nil
        }
        if selectedClaudeSessionsSessionID == sessionID {
            selectedClaudeSessionsSessionID = nil
            selectedClaudeSessions = []
            selectedClaudeSessionsErrorMessage = nil
        }
        codexResumeInProgressThreadID = nil
        codexResumeStatusMessage = nil
        codexResumeErrorMessage = nil
        claudeResumeInProgressSessionID = nil
        claudeResumeStatusMessage = nil
        claudeResumeErrorMessage = nil
        sendingMessageSessionID = nil
        sendingMessageSteerMode = nil
        sendMessageStatusMessage = nil
        sendMessageErrorMessage = nil
    }

    public func setSessionTitle(
        sessionID: String,
        title: String?,
        serverURLString: String,
        token: String
    ) async {
        renamingSessionIDs.insert(sessionID)
        defer { renamingSessionIDs.remove(sessionID) }

        do {
            let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let persistedTitle: String? = normalizedTitle?.isEmpty == true ? nil : normalizedTitle
            try await titleUseCase.setSessionTitle(
                serverURLString: serverURLString,
                token: token,
                sessionID: sessionID,
                title: persistedTitle
            )

            if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
                let session = sessions[index]
                sessions[index] = APISession(
                    id: session.id,
                    displayName: persistedTitle,
                    seq: session.seq,
                    active: session.active,
                    activeAt: session.activeAt,
                    createdAt: session.createdAt,
                    updatedAt: session.updatedAt,
                    metadataVersion: session.metadataVersion,
                    metadata: session.metadata,
                    agentState: session.agentState,
                    agentStateVersion: session.agentStateVersion,
                    dataEncryptionKey: session.dataEncryptionKey,
                    lastMessage: session.lastMessage
                )
                refreshQueuedComposerMessagesCache(from: sessions)
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func applyQueuedComposerSnapshot(
        for sessionID: String,
        steerMode: APISessionSteerMode,
        sentText: String,
        response: APISessionSendMessageResult
    ) {
        let responseMessages = normalizeQueuedComposerMessageTexts(
            (response.queuedMessages ?? []).map { $0 as Any }
        )

        var next = queuedComposerMessagesBySessionID
        if !responseMessages.isEmpty {
            next[sessionID] = responseMessages
        } else if let queueCount = response.queueCount, queueCount <= 0 {
            next[sessionID] = nil
        } else if steerMode == .queue {
            let normalizedText = sentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedText.isEmpty {
                var existing = next[sessionID] ?? []
                existing.append(normalizedText)
                next[sessionID] = normalizeQueuedComposerMessageTexts(existing.map { $0 as Any })
            }
        }

        if next != queuedComposerMessagesBySessionID {
            queuedComposerMessagesBySessionID = next
        }
    }

    private func refreshQueuedComposerMessagesCache(from sessions: [APISession]) {
        var next: [String: [String]] = [:]
        next.reserveCapacity(sessions.count)

        for session in sessions {
            let decoded = decodeQueuedComposerState(from: session)
            if !decoded.messages.isEmpty {
                next[session.id] = decoded.messages
                continue
            }
            if let queueCount = decoded.queueCount, queueCount <= 0 {
                continue
            }
            if let existing = queuedComposerMessagesBySessionID[session.id], !existing.isEmpty {
                next[session.id] = existing
            }
        }

        if next != queuedComposerMessagesBySessionID {
            queuedComposerMessagesBySessionID = next
        }
    }

    private func decodeQueuedComposerState(from session: APISession) -> (messages: [String], queueCount: Int?) {
        let payload = SessionPayloadValueResolver.decodeJSONObject(
            payload: session.agentState,
            dataEncryptionKey: session.dataEncryptionKey
        )
        guard !payload.isEmpty else {
            return ([], nil)
        }

        if let queue = payload["queue"] as? [String: Any] {
            let queueCount = normalizedNonNegativeInt(from: queue["queuedCount"])
            let candidates: [Any?] = [
                queue["pendingMessages"],
                queue["queuedMessages"],
                queue["messages"],
            ]
            for candidate in candidates {
                let messages = normalizeQueuedComposerMessageTexts(arrayValue(from: candidate))
                if !messages.isEmpty {
                    return (messages, queueCount)
                }
            }
            if let queueCount {
                return ([], queueCount)
            }
        }

        let fallbackCandidates: [Any?] = [
            payload["pendingMessages"],
            payload["queuedMessages"],
            payload["messages"],
        ]
        for candidate in fallbackCandidates {
            let messages = normalizeQueuedComposerMessageTexts(arrayValue(from: candidate))
            if !messages.isEmpty {
                return (messages, nil)
            }
        }

        return ([], nil)
    }

    private func arrayValue(from value: Any?) -> [Any] {
        guard let value else { return [] }
        if let array = value as? [Any] {
            return array
        }
        return []
    }

    private func normalizeQueuedComposerMessageTexts(_ values: [Any]) -> [String] {
        var normalized: [String] = []
        normalized.reserveCapacity(values.count)

        for value in values {
            if let text = value as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                normalized.append(trimmed)
                continue
            }
            if let payload = value as? [String: Any] {
                let textCandidates: [Any?] = [payload["text"], payload["message"], payload["value"]]
                for candidate in textCandidates {
                    guard let raw = candidate as? String else { continue }
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    normalized.append(trimmed)
                    break
                }
            }
        }

        var deduped: [String] = []
        deduped.reserveCapacity(normalized.count)
        for message in normalized where !deduped.contains(message) {
            deduped.append(message)
        }
        return deduped
    }

    private func normalizedNonNegativeInt(from value: Any?) -> Int? {
        if let intValue = value as? Int {
            return max(0, intValue)
        }
        if let number = value as? NSNumber {
            return max(0, number.intValue)
        }
        if let string = value as? String, let parsed = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return max(0, parsed)
        }
        return nil
    }

    @discardableResult
    private func cacheMessages(_ messages: [APISessionMessage], for sessionID: String) -> [APISessionMessage] {
        let orderedMessages = normalizeMessageOrder(messages)
        let normalizedMessages: [APISessionMessage]
        if orderedMessages.count > CachePolicy.maxMessagesPerSession {
            normalizedMessages = Array(orderedMessages.suffix(CachePolicy.maxMessagesPerSession))
        } else {
            normalizedMessages = orderedMessages
        }

        if messagesBySessionID[sessionID] != normalizedMessages {
            messagesBySessionID[sessionID] = normalizedMessages
        }
        touchCache(sessionID: sessionID)
        evictCacheIfNeeded(preserving: selectedSessionID)
        return normalizedMessages
    }

    private func mergeFetchedMessages(_ fetchedMessages: [APISessionMessage], for sessionID: String) -> [APISessionMessage] {
        guard let cachedMessages = messagesBySessionID[sessionID], !cachedMessages.isEmpty else {
            return fetchedMessages
        }
        guard fetchedMessages.count >= cachedMessages.count else {
            return fetchedMessages
        }

        for index in cachedMessages.indices where cachedMessages[index] != fetchedMessages[index] {
            return fetchedMessages
        }

        if fetchedMessages.count == cachedMessages.count {
            return cachedMessages
        }
        return cachedMessages + Array(fetchedMessages.dropFirst(cachedMessages.count))
    }

    private func normalizeMessageOrder(_ messages: [APISessionMessage]) -> [APISessionMessage] {
        messages.sorted { lhs, rhs in
            if lhs.seq != rhs.seq {
                return lhs.seq < rhs.seq
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt < rhs.updatedAt
            }
            return lhs.id < rhs.id
        }
    }

    private func appendOptimisticUserMessageIfPossible(for sessionID: String, text: String) {
        guard selectedSessionID == sessionID else { return }
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return }

        let currentMessages = messagesBySessionID[sessionID] ?? selectedSessionMessages
        let timestamp = Date().timeIntervalSince1970
        let optimisticID = "optimistic-\(UUID().uuidString.lowercased())"
        let optimisticMessage = APISessionMessage(
            id: optimisticID,
            seq: (currentMessages.last?.seq ?? 0) + 1,
            localId: optimisticID,
            content: APIEncryptedMessageContent(
                t: "optimistic-user",
                c: makeOptimisticUserPayload(text: normalizedText)
            ),
            createdAt: timestamp,
            updatedAt: timestamp
        )

        let normalizedMessages = cacheMessages(currentMessages + [optimisticMessage], for: sessionID)
        setSelectedSessionMessagesIfNeeded(normalizedMessages)
    }

    private func makeOptimisticUserPayload(text: String) -> String {
        let payload: [String: Any] = [
            "role": "user",
            "content": [
                "type": "text",
                "text": text,
            ],
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let encodedPayload = String(data: data, encoding: .utf8) else {
            return text
        }
        return encodedPayload
    }

    private func setSelectedSessionMessagesIfNeeded(_ messages: [APISessionMessage]) {
        guard selectedSessionMessages != messages else { return }
        selectedSessionMessages = messages
    }

    private func runSelectedSessionMessagesPolling(
        taskID: UUID,
        sessionID: String,
        serverURLString: String,
        token: String,
        interval: Duration
    ) async {
        await loadMessages(
            for: sessionID,
            serverURLString: serverURLString,
            token: token
        )

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: interval)
            } catch is CancellationError {
                break
            } catch {
                break
            }
            if Task.isCancelled {
                break
            }

            await loadMessages(
                for: sessionID,
                serverURLString: serverURLString,
                token: token,
                showsLoadingState: false,
                clearsMessagesOnFailure: false
            )
        }

        clearSelectedSessionMessagesPollingTaskIfNeeded(taskID: taskID)
    }

    private func clearSelectedSessionMessagesPollingTaskIfNeeded(taskID: UUID) {
        guard selectedSessionMessagesPollingTaskID == taskID else { return }
        selectedSessionMessagesPollingTask = nil
        selectedSessionMessagesPollingTaskID = nil
    }

    private func touchCache(sessionID: String) {
        messageCacheLRU.removeAll { $0 == sessionID }
        messageCacheLRU.append(sessionID)
    }

    private func evictCacheIfNeeded(preserving preservedSessionID: String?) {
        while messagesBySessionID.count > CachePolicy.maxCachedSessions {
            guard let oldestSessionID = messageCacheLRU.first else { return }
            if let preservedSessionID, oldestSessionID == preservedSessionID {
                messageCacheLRU.removeFirst()
                messageCacheLRU.append(oldestSessionID)
                continue
            }

            messageCacheLRU.removeFirst()
            messagesBySessionID[oldestSessionID] = nil
        }
    }

    private func mergeLatestRows(_ latestRows: [APISession], into existingRows: [APISession]) -> [APISession] {
        var byID: [String: APISession] = [:]
        byID.reserveCapacity(existingRows.count + latestRows.count)

        for row in existingRows {
            byID[row.id] = row
        }
        for row in latestRows {
            byID[row.id] = row
        }

        return byID.values.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.id > rhs.id
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }
}
