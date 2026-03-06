import Foundation
import CoreKit
import FeatureNewSession

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
    @Published public private(set) var upstreamSessions: [SessionLinkedUpstreamSession] = []
    @Published public private(set) var isLoadingUpstreamSessions = false
    @Published public private(set) var upstreamSessionsErrorMessage: String?
    @Published public private(set) var linkingUpstreamSessionID: String?
    @Published public private(set) var upstreamSessionStatusMessage: String?
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
    @Published private(set) var queuedComposerDraftsBySessionID: [String: [SessionQueuedComposerDraft]] = [:]
    private var queuedComposerAwaitingTurnCompletionSessionIDs: Set<String> = []
    private var queuedComposerLastDispatchAtBySessionID: [String: TimeInterval] = [:]

    private let loader: any SessionsLoading
    private let pageLoader: any SessionsPageLoading
    private let poller: any SessionsPolling
    private let messageLoader: any SessionsMessagesLoading
    private let upstreamSessionsLoader: (any SessionUpstreamSessionsLoadingAction)?
    private let upstreamSessionLinker: (any NewSessionSpawningAction)?
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
        upstreamSessionsLoader: (any SessionUpstreamSessionsLoadingAction)? = nil,
        upstreamSessionLinker: (any NewSessionSpawningAction)? = nil,
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
        self.upstreamSessionsLoader = upstreamSessionsLoader
        self.upstreamSessionLinker = upstreamSessionLinker
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
        (queuedComposerDraftsBySessionID[sessionID] ?? []).map(\.previewText)
    }

    func takeQueuedComposerDraft(for sessionID: String, at index: Int) -> SessionQueuedComposerDraft? {
        guard var queued = queuedComposerDraftsBySessionID[sessionID] else { return nil }
        guard queued.indices.contains(index) else { return nil }
        let draft = queued.remove(at: index)
        if queued.isEmpty {
            queuedComposerDraftsBySessionID[sessionID] = nil
        } else {
            queuedComposerDraftsBySessionID[sessionID] = queued
        }
        return draft
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
            nextCursor = firstPage.nextCursor
            hasMoreSessions = firstPage.hasNext
            errorMessage = nil
            await loadUpstreamSessions(
                serverURLString: serverURLString,
                token: token
            )
            await maybeDispatchQueuedComposerDrafts(
                serverURLString: serverURLString,
                token: token
            )
        } catch {
            sessions = []
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
                await loadUpstreamSessions(
                    serverURLString: serverURLString,
                    token: token
                )
                errorMessage = nil
                isLoading = false
                await maybeDispatchQueuedComposerDrafts(
                    serverURLString: serverURLString,
                    token: token
                )
            }
        } catch is CancellationError {
            // Stream cancellation is expected when the view task is torn down.
        } catch {
            sessions = []
            nextCursor = nil
            hasMoreSessions = false
            upstreamSessions = []
            upstreamSessionsErrorMessage = nil
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
            self.nextCursor = page.nextCursor
            hasMoreSessions = page.hasNext
            errorMessage = nil
            await loadUpstreamSessions(
                serverURLString: serverURLString,
                token: token
            )
            await maybeDispatchQueuedComposerDrafts(
                serverURLString: serverURLString,
                token: token
            )
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

    public func loadUpstreamSessions(
        serverURLString: String,
        token: String
    ) async {
        guard let upstreamSessionsLoader else {
            upstreamSessions = []
            upstreamSessionsErrorMessage = nil
            return
        }

        isLoadingUpstreamSessions = true
        defer { isLoadingUpstreamSessions = false }

        do {
            let rows = try await upstreamSessionsLoader.loadUpstreamSessions(
                serverURLString: serverURLString,
                token: token
            )
            upstreamSessions = filterMirroredUpstreamSessions(rows)
            upstreamSessionsErrorMessage = nil
        } catch {
            upstreamSessions = []
            upstreamSessionsErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func linkUpstreamSession(
        _ row: SessionLinkedUpstreamSession,
        serverURLString: String,
        token: String
    ) async -> String? {
        guard let upstreamSessionLinker else {
            upstreamSessionStatusMessage = "Upstream linking is unavailable in this build"
            return nil
        }

        linkingUpstreamSessionID = row.id
        upstreamSessionStatusMessage = nil
        defer {
            if linkingUpstreamSessionID == row.id {
                linkingUpstreamSessionID = nil
            }
        }

        let directory = row.summary.cwd?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !directory.isEmpty else {
            upstreamSessionStatusMessage = "Missing working directory for upstream session"
            return nil
        }

        do {
            let response = try await upstreamSessionLinker.spawnSession(
                serverURLString: serverURLString,
                token: token,
                machineID: row.machineID,
                directory: directory,
                agent: {
                    switch row.summary.provider {
                    case .codex:
                        return .codex
                    case .claude:
                        return .claude
                    case .gemini:
                        return .gemini
                    }
                }(),
                approvedNewDirectoryCreation: true,
                codexResumeThreadID: row.summary.provider == .codex ? row.summary.id : nil,
                claudeResumeSessionID: row.summary.provider == .claude ? row.summary.id : nil,
                sessionToken: nil,
                environmentVariables: [:],
                model: nil,
                reasoningEffort: nil
            )
            if let sessionID = response.sessionID, !sessionID.isEmpty {
                upstreamSessionStatusMessage = "Linked \(row.summary.provider.displayName) session \(sessionID)"
            } else {
                upstreamSessionStatusMessage = "Linked \(row.summary.provider.displayName) session"
            }
            await load(serverURLString: serverURLString, token: token)
            return response.sessionID
        } catch {
            upstreamSessionStatusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
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
        attachments: [SessionComposerImageAttachment] = [],
        steerMode: APISessionSteerMode,
        permissionMode: APISessionMessagePermissionMode? = nil,
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
            _ = try await messageSender.sendMessage(
                serverURLString: serverURLString,
                token: token,
                sessionID: sessionID,
                text: text,
                attachments: attachments,
                steerMode: steerMode,
                permissionMode: permissionMode,
                modelOverride: modelOverride,
                effortOverride: effortOverride
            )
            sendMessageStatusMessage = nil
            sendMessageErrorMessage = nil
            appendOptimisticUserMessageIfPossible(
                for: sessionID,
                text: text,
                attachments: attachments
            )
            return true
        } catch {
            sendMessageStatusMessage = nil
            sendMessageErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func enqueueComposerDraft(
        for sessionID: String,
        text: String,
        attachments: [SessionComposerImageAttachment],
        serverURLString: String,
        token: String
    ) async -> Bool {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty || !attachments.isEmpty else { return false }

        let draft = SessionQueuedComposerDraft(
            text: normalizedText,
            attachments: attachments
        )

        var queued = queuedComposerDraftsBySessionID[sessionID] ?? []
        queued.append(draft)
        queuedComposerDraftsBySessionID[sessionID] = queued

        await maybeDispatchQueuedComposerDrafts(
            serverURLString: serverURLString,
            token: token
        )
        return true
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
            queuedComposerDraftsBySessionID[sessionID] = nil
            queuedComposerAwaitingTurnCompletionSessionIDs.remove(sessionID)
            queuedComposerLastDispatchAtBySessionID[sessionID] = nil
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

            if let session = sessions.first(where: { $0.id == sessionID }) {
                let updatedSession = APISession(
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
                replaceSession(updatedSession)
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func maybeDispatchQueuedComposerDrafts(
        serverURLString: String,
        token: String
    ) async {
        guard sendingMessageSessionID == nil else { return }

        for session in sessions {
            guard canDispatchQueuedComposerDraft(for: session) else { continue }
            await dispatchNextQueuedComposerDraft(
                for: session.id,
                serverURLString: serverURLString,
                token: token
            )
            return
        }
    }

    private func canDispatchQueuedComposerDraft(for session: APISession) -> Bool {
        guard let queued = queuedComposerDraftsBySessionID[session.id], !queued.isEmpty else {
            return false
        }
        if queuedComposerAwaitingTurnCompletionSessionIDs.contains(session.id) {
            let decodedAgentState = SessionPayloadValueResolver.decodeJSONObject(
                payload: session.agentState,
                dataEncryptionKey: session.dataEncryptionKey
            )
            let decodedMetadata = SessionPayloadValueResolver.decodeJSONObject(
                payload: session.metadata,
                dataEncryptionKey: session.dataEncryptionKey
            )
            let hasPendingApproval = SessionApprovalStateEvaluator.hasPendingApprovalRequest(
                agentState: decodedAgentState,
                metadata: decodedMetadata
            )
            if session.active || hasPendingApproval {
                return false
            }
            if let lastDispatchAt = queuedComposerLastDispatchAtBySessionID[session.id],
               session.updatedAt <= lastDispatchAt {
                return false
            }
            queuedComposerAwaitingTurnCompletionSessionIDs.remove(session.id)
            queuedComposerLastDispatchAtBySessionID[session.id] = nil
        }
        return !session.active
    }

    private func dispatchNextQueuedComposerDraft(
        for sessionID: String,
        serverURLString: String,
        token: String
    ) async {
        guard let draft = queuedComposerDraftsBySessionID[sessionID]?.first else { return }
        let sent = await sendMessage(
            for: sessionID,
            text: draft.text,
            attachments: draft.attachments,
            steerMode: .immediate,
            permissionMode: nil,
            modelOverride: .inherit,
            effortOverride: .inherit,
            serverURLString: serverURLString,
            token: token
        )
        guard sent else { return }

        var queued = queuedComposerDraftsBySessionID[sessionID] ?? []
        if !queued.isEmpty {
            queued.removeFirst()
        }
        if queued.isEmpty {
            queuedComposerDraftsBySessionID[sessionID] = nil
        } else {
            queuedComposerDraftsBySessionID[sessionID] = queued
        }
        queuedComposerAwaitingTurnCompletionSessionIDs.insert(sessionID)
        queuedComposerLastDispatchAtBySessionID[sessionID] = Date().timeIntervalSince1970
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
        sessionsMergeFetchedMessages(
            fetchedMessages: fetchedMessages,
            cachedMessages: messagesBySessionID[sessionID]
        )
    }

    private func normalizeMessageOrder(_ messages: [APISessionMessage]) -> [APISessionMessage] {
        sessionsNormalizeMessageOrder(messages)
    }

    private func appendOptimisticUserMessageIfPossible(
        for sessionID: String,
        text: String,
        attachments: [SessionComposerImageAttachment]
    ) {
        guard selectedSessionID == sessionID else { return }
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty || !attachments.isEmpty else { return }

        let currentMessages = messagesBySessionID[sessionID] ?? selectedSessionMessages
        let timestamp = Date().timeIntervalSince1970
        let optimisticID = "optimistic-\(UUID().uuidString.lowercased())"
        let optimisticMessage = APISessionMessage(
            id: optimisticID,
            seq: (currentMessages.last?.seq ?? 0) + 1,
            localId: optimisticID,
            content: APIEncryptedMessageContent(
                t: "optimistic-user",
                c: makeOptimisticUserPayload(
                    text: normalizedText,
                    imageDataURLs: attachments.map(\.dataURLString)
                )
            ),
            createdAt: timestamp,
            updatedAt: timestamp
        )

        let normalizedMessages = cacheMessages(currentMessages + [optimisticMessage], for: sessionID)
        setSelectedSessionMessagesIfNeeded(normalizedMessages)
    }

    private func makeOptimisticUserPayload(text: String, imageDataURLs: [String]) -> String {
        sessionsMakeOptimisticUserPayload(text: text, imageDataURLs: imageDataURLs)
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
        await refreshSelectedSessionSnapshot(
            sessionID: sessionID,
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
            await refreshSelectedSessionSnapshot(
                sessionID: sessionID,
                serverURLString: serverURLString,
                token: token
            )
        }

        clearSelectedSessionMessagesPollingTaskIfNeeded(taskID: taskID)
    }

    private func refreshSelectedSessionSnapshot(
        sessionID: String,
        serverURLString: String,
        token: String
    ) async {
        do {
            let rows = try await loader.loadSessions(
                serverURLString: serverURLString,
                token: token
            )
            sessions = mergeLatestRows(rows, into: sessions)
            await maybeDispatchQueuedComposerDrafts(
                serverURLString: serverURLString,
                token: token
            )

            // If the selected session vanished server-side, clear detail state immediately.
            if !rows.isEmpty &&
                selectedSessionID == sessionID &&
                !sessions.contains(where: { $0.id == sessionID }) {
                clearDetailSelectionIfNeeded(sessionID: sessionID)
            }
        } catch {
            // Keep last known detail state; transient refresh failures should not clear the transcript UI.
        }
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
        sessionsMergeLatestRows(latestRows, into: existingRows)
    }

    private func filterMirroredUpstreamSessions(
        _ rows: [SessionLinkedUpstreamSession]
    ) -> [SessionLinkedUpstreamSession] {
        let mirroredKeys: Set<String> = Set(
            sessions.compactMap { session in
                let metadata = SessionPayloadValueResolver.decodeJSONObject(
                    payload: session.metadata,
                    dataEncryptionKey: session.dataEncryptionKey
                )
                let agentSessionId = SessionPayloadValueResolver.firstString(
                    in: [metadata],
                    keys: ["agentSessionId", "agent_session_id"]
                )?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let agentSessionId, !agentSessionId.isEmpty else {
                    return nil
                }
                let flavor = SessionPayloadValueResolver.firstString(
                    in: [metadata],
                    keys: ["flavor"]
                )?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let machineId = SessionPayloadValueResolver.firstString(
                    in: [metadata],
                    keys: ["machineId", "machine_id"]
                )?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let flavor, let machineId, !machineId.isEmpty else {
                    return nil
                }
                return "\(machineId)|\(flavor)|\(agentSessionId)"
            }
        )

        return rows.filter { !mirroredKeys.contains($0.id) }
    }

    private func replaceSession(_ session: APISession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        var nextSessions = sessions
        nextSessions[index] = session
        sessions = nextSessions
    }
}
