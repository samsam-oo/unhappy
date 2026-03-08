import Foundation
import CoreKit

@MainActor
public final class SessionsViewModel: ObservableObject {
    private enum CachePolicy {
        static let maxCachedSessions = 4
        static let maxMessagesPerSession = 150
    }

    private enum SyncPolicy {
        static let supportingDataRefreshInterval: TimeInterval = 15
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
    @Published public private(set) var projects: [SessionMachineProject] = []
    @Published public private(set) var isLoadingProjects = false
    @Published public private(set) var projectsErrorMessage: String?
    @Published public private(set) var openingProjectID: String?
    @Published public private(set) var removingProjectID: String?
    @Published public private(set) var upstreamSessions: [SessionLinkedUpstreamSession] = []
    @Published public private(set) var isLoadingUpstreamSessions = false
    @Published public private(set) var upstreamSessionsErrorMessage: String?
    @Published public private(set) var deletingSessionIDs: Set<String> = []
    @Published public private(set) var renamingSessionIDs: Set<String> = []
    @Published public private(set) var sendingMessageSessionID: String?
    @Published public private(set) var sendingMessageSteerMode: APISessionSteerMode?
    @Published public private(set) var sendMessageStatusMessage: String?
    @Published public private(set) var sendMessageErrorMessage: String?
    @Published private(set) var queuedComposerDraftsBySessionID: [String: [SessionQueuedComposerDraft]] = [:]
    private var queuedComposerAwaitingTurnCompletionSessionIDs: Set<String> = []
    private var queuedComposerLastDispatchAtBySessionID: [String: TimeInterval] = [:]
    private var attemptedDuplicateCleanupSessionIDs: Set<String> = []

    private let loader: any SessionsLoading
    private let pageLoader: any SessionsPageLoading
    private let poller: any SessionsPolling
    private let messageLoader: any SessionsMessagesLoading
    private let projectsLoader: (any SessionProjectsLoadingAction)?
    private let projectOpener: (any SessionProjectOpeningAction)?
    private let projectRemover: (any SessionProjectRemovingAction)?
    private let upstreamSessionsLoader: (any SessionUpstreamSessionsLoadingAction)?
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
    private var lastSupportingDataSyncAt: TimeInterval?
    private var lastSupportingDataFingerprint: String?

    public init(
        loader: any SessionsLoading,
        pageLoader: any SessionsPageLoading,
        poller: any SessionsPolling,
        messageLoader: any SessionsMessagesLoading,
        projectsLoader: (any SessionProjectsLoadingAction)? = nil,
        projectOpener: (any SessionProjectOpeningAction)? = nil,
        projectRemover: (any SessionProjectRemovingAction)? = nil,
        upstreamSessionsLoader: (any SessionUpstreamSessionsLoadingAction)? = nil,
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
        self.projectsLoader = projectsLoader
        self.projectOpener = projectOpener
        self.projectRemover = projectRemover
        self.upstreamSessionsLoader = upstreamSessionsLoader
        self.sessionModelsLoader = sessionModelsLoader
        self.spawnUseCase = spawnUseCase
        self.messageSender = messageSender
        self.preDeleteKiller = preDeleteKiller
        self.deleteUseCase = deleteUseCase
        self.titleUseCase = titleUseCase
    }

    public convenience init(
        service: any SessionsFetching & SessionsPagingFetching & SessionMessagesFetching & SessionDeleting & SessionTitleUpdating & SessionSpawning
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

    public func isRemoving(projectID: String) -> Bool {
        removingProjectID == projectID
    }

    public func isTrackedProject(
        machineID: String,
        projectPath: String
    ) -> Bool {
        matchingTrackedProject(
            machineID: machineID,
            projectPath: projectPath
        )?.summary.openedExplicitly == true
    }

    public func sendingSteerMode(sessionID: String) -> APISessionSteerMode? {
        guard sendingMessageSessionID == sessionID else { return nil }
        return sendingMessageSteerMode
    }

    public func queuedComposerMessages(for sessionID: String) -> [String] {
        (queuedComposerDraftsBySessionID[sessionID] ?? []).map(\.previewText)
    }

    public func messages(for sessionID: String) -> [APISessionMessage] {
        if let cachedMessages = messagesBySessionID[sessionID] {
            return cachedMessages
        }
        if selectedSessionID == sessionID {
            return selectedSessionMessages
        }
        return []
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
            await cleanupProviderBackedSessions(
                serverURLString: serverURLString,
                token: token
            )
            await cleanupMirroredDuplicateSessions(
                serverURLString: serverURLString,
                token: token
            )
            nextCursor = firstPage.nextCursor
            hasMoreSessions = firstPage.hasNext
            errorMessage = nil
            await refreshSupportingProjectContent(
                serverURLString: serverURLString,
                token: token,
                force: true
            )
            await maybeDispatchQueuedComposerDrafts(
                serverURLString: serverURLString,
                token: token
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func startPolling(
        serverURLString: String,
        token: String,
        interval: Duration = .seconds(15)
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
                await cleanupProviderBackedSessions(
                    serverURLString: serverURLString,
                    token: token
                )
                await cleanupMirroredDuplicateSessions(
                    serverURLString: serverURLString,
                    token: token
                )
                await refreshSupportingProjectContent(
                    serverURLString: serverURLString,
                    token: token,
                    force: false
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
            await cleanupProviderBackedSessions(
                serverURLString: serverURLString,
                token: token
            )
            await cleanupMirroredDuplicateSessions(
                serverURLString: serverURLString,
                token: token
            )
            self.nextCursor = page.nextCursor
            hasMoreSessions = page.hasNext
            errorMessage = nil
            await refreshSupportingProjectContent(
                serverURLString: serverURLString,
                token: token,
                force: false
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

        let snapshot = await refreshMessagesSnapshot(
            for: sessionID,
            serverURLString: serverURLString,
            token: token,
            clearsMessagesOnFailure: clearsMessagesOnFailure
        )
        if selectedSessionID == sessionID {
            setSelectedSessionMessagesIfNeeded(snapshot.messages)
            selectedSessionErrorMessage = snapshot.errorMessage
        }
    }

    public func refreshMessagesSnapshot(
        for sessionID: String,
        serverURLString: String,
        token: String,
        clearsMessagesOnFailure: Bool = true
    ) async -> SessionMessagesSnapshot {
        let cachedMessages = messagesBySessionID[sessionID] ?? []

        do {
            let fetchedMessages = try await messageLoader.loadMessages(
                serverURLString: serverURLString,
                token: token,
                sessionID: sessionID
            )
            let mergedMessages = mergeFetchedMessages(fetchedMessages, for: sessionID)
            let normalizedMessages = cacheMessages(mergedMessages, for: sessionID)
            return SessionMessagesSnapshot(
                sessionID: sessionID,
                messages: normalizedMessages,
                errorMessage: nil,
                sessionMissing: false
            )
        } catch let apiError as SessionsAPIError {
            if case .invalidHTTPStatus(404) = apiError {
                sessions.removeAll { $0.id == sessionID }
                messagesBySessionID[sessionID] = nil
                messageCacheLRU.removeAll { $0 == sessionID }
                return SessionMessagesSnapshot(
                    sessionID: sessionID,
                    messages: [],
                    errorMessage: "Session no longer exists on server.",
                    sessionMissing: true
                )
            }
            return SessionMessagesSnapshot(
                sessionID: sessionID,
                messages: clearsMessagesOnFailure ? [] : cachedMessages,
                errorMessage: apiError.errorDescription ?? apiError.localizedDescription,
                sessionMissing: false
            )
        } catch {
            return SessionMessagesSnapshot(
                sessionID: sessionID,
                messages: clearsMessagesOnFailure ? [] : cachedMessages,
                errorMessage: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                sessionMissing: false
            )
        }
    }

    public func refreshAndSelectSession(
        sessionID: String,
        serverURLString: String,
        token: String,
        maxAttempts: Int = 3
    ) async -> APISession? {
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else { return nil }
        let attempts = max(1, maxAttempts)

        for attempt in 0..<attempts {
            await load(serverURLString: serverURLString, token: token)
            if let resolvedSession = sessions.first(where: { $0.id == normalizedSessionID }) {
                await loadMessages(
                    for: normalizedSessionID,
                    serverURLString: serverURLString,
                    token: token
                )
                return resolvedSession
            }

            if attempt + 1 < attempts {
                try? await Task.sleep(for: .milliseconds(250))
            }
        }

        return nil
    }

    public func loadUpstreamSessions(
        serverURLString: String,
        token: String
    ) async {
        await loadUpstreamSessions(
            serverURLString: serverURLString,
            token: token,
            projectsToSync: projectsForUpstreamSync()
        )
    }

    private func loadUpstreamSessions(
        serverURLString: String,
        token: String,
        projectsToSync: [SessionMachineProject]
    ) async {
        guard let upstreamSessionsLoader else {
            upstreamSessions = []
            upstreamSessionsErrorMessage = nil
            return
        }
        guard !isLoadingUpstreamSessions else { return }

        isLoadingUpstreamSessions = true
        defer { isLoadingUpstreamSessions = false }

        do {
            let rows = try await upstreamSessionsLoader.loadUpstreamSessions(
                serverURLString: serverURLString,
                token: token,
                projects: projectsToSync
            )
            upstreamSessions = rows
            upstreamSessionsErrorMessage = nil
        } catch {
            upstreamSessionsErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func loadProjects(
        serverURLString: String,
        token: String
    ) async {
        guard let projectsLoader else {
            projects = []
            projectsErrorMessage = nil
            return
        }
        guard !isLoadingProjects else { return }

        isLoadingProjects = true
        defer { isLoadingProjects = false }

        do {
            projects = try await projectsLoader.loadProjects(
                serverURLString: serverURLString,
                token: token
            ).filter(\.summary.openedExplicitly)
            projectsErrorMessage = nil
        } catch {
            projectsErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func refreshSupportingProjectContent(
        serverURLString: String,
        token: String,
        force: Bool
    ) async {
        let fingerprint = supportingDataFingerprint()
        let now = Date().timeIntervalSince1970
        let isStale: Bool
        if let lastSupportingDataSyncAt {
            isStale = now - lastSupportingDataSyncAt >= SyncPolicy.supportingDataRefreshInterval
        } else {
            isStale = true
        }

        guard force || isStale || lastSupportingDataFingerprint != fingerprint else {
            return
        }

        await loadProjects(
            serverURLString: serverURLString,
            token: token
        )
        await loadUpstreamSessions(
            serverURLString: serverURLString,
            token: token,
            projectsToSync: projectsForUpstreamSync()
        )
        lastSupportingDataFingerprint = supportingDataFingerprint()
        lastSupportingDataSyncAt = Date().timeIntervalSince1970
    }

    public func openProject(
        machineID: String,
        machineDisplayName: String,
        projectPath: String,
        serverURLString: String,
        token: String
    ) async {
        guard let projectOpener else {
            projectsErrorMessage = "Project opening is unavailable in this build"
            return
        }

        let projectID = "\(machineID)|\(projectPath)"
        openingProjectID = projectID
        defer {
            if openingProjectID == projectID {
                openingProjectID = nil
            }
        }

        do {
            let openedProject = try await projectOpener.openProject(
                serverURLString: serverURLString,
                token: token,
                machineID: machineID,
                machineDisplayName: machineDisplayName,
                path: projectPath
            )
            if !projects.contains(where: { $0.id == openedProject.id }) {
                projects.insert(openedProject, at: 0)
            }
            await refreshSupportingProjectContent(
                serverURLString: serverURLString,
                token: token,
                force: true
            )
        } catch {
            projectsErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @discardableResult
    public func removeProject(
        machineID: String,
        projectPath: String,
        serverURLString: String,
        token: String
    ) async -> Bool {
        guard let projectRemover else {
            projectsErrorMessage = "Project removal is unavailable in this build"
            return false
        }

        let projectID = "\(machineID)|\(projectPath)"
        removingProjectID = projectID
        defer {
            if removingProjectID == projectID {
                removingProjectID = nil
            }
        }

        do {
            _ = try await projectRemover.removeProject(
                serverURLString: serverURLString,
                token: token,
                machineID: machineID,
                path: projectPath
            )
            projects.removeAll { $0.id == projectID }
            projectsErrorMessage = nil
            await refreshSupportingProjectContent(
                serverURLString: serverURLString,
                token: token,
                force: true
            )
            return true
        } catch {
            projectsErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
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

    public func loadFirstMessagePreview(
        for sessionID: String,
        dataEncryptionKey: String?,
        serverURLString: String,
        token: String
    ) async -> String? {
        do {
            let messages = try await messageLoader.loadMessages(
                serverURLString: serverURLString,
                token: token,
                sessionID: sessionID
            )
            return SessionFirstMessagePreviewResolver.resolve(
                from: messages,
                dataEncryptionKey: dataEncryptionKey
            )
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
                errorMessage = "Archived session, but failed to terminate the local session process: \(killFailureMessage)"
            } else {
                errorMessage = nil
            }
        } catch {
            let deleteFailureMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if let killFailureMessage {
                errorMessage = "Failed to terminate the local session process: \(killFailureMessage). Session archive also failed: \(deleteFailureMessage)"
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
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty || !attachments.isEmpty else { return }

        let currentMessages = messagesBySessionID[sessionID]
            ?? (selectedSessionID == sessionID ? selectedSessionMessages : [])
        let timestamp = Date().timeIntervalSince1970
        let optimisticID = "optimistic-\(UUID().uuidString.lowercased())"
        let optimisticMessage = APISessionMessage(
            id: optimisticID,
            seq: (currentMessages.last?.seq ?? 0) + 1,
            localId: optimisticID,
            content: APIEncryptedMessageContent(
                type: "optimistic-user",
                payload: makeOptimisticUserPayload(
                    text: normalizedText,
                    imageDataURLs: attachments.map(\.dataURLString)
                )
            ),
            createdAt: timestamp,
            updatedAt: timestamp
        )

        let normalizedMessages = cacheMessages(currentMessages + [optimisticMessage], for: sessionID)
        if selectedSessionID == sessionID {
            setSelectedSessionMessagesIfNeeded(normalizedMessages)
        }
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

    private func projectsForUpstreamSync() -> [SessionMachineProject] {
        projects.filter(\.summary.openedExplicitly)
    }

    private func supportingDataFingerprint() -> String {
        let trackedProjectIDs = projects.compactMap { project in
            canonicalProjectID(
                machineID: project.machineID,
                projectPath: project.summary.path
            )
        }
        .sorted()
        return trackedProjectIDs.joined(separator: ",")
    }

    private func matchingTrackedProject(
        machineID: String,
        projectPath: String
    ) -> SessionMachineProject? {
        projects.first { project in
            canonicalProjectID(
                machineID: project.machineID,
                projectPath: project.summary.path
            ) == canonicalProjectID(
                machineID: machineID,
                projectPath: projectPath
            )
        }
    }

    private func canonicalProjectID(
        machineID: String,
        projectPath: String
    ) -> String? {
        guard let normalizedPath = SessionProjectPathCanonicalizer.canonicalPath(projectPath) else {
            return nil
        }
        return "\(machineID)|\(normalizedPath)"
    }

    private func cleanupMirroredDuplicateSessions(
        serverURLString: String,
        token: String
    ) async {
        let duplicateSessionIDs = redundantMirroredSessionIDs().filter { sessionID in
            !attemptedDuplicateCleanupSessionIDs.contains(sessionID)
        }
        guard !duplicateSessionIDs.isEmpty else { return }

        for sessionID in duplicateSessionIDs {
            attemptedDuplicateCleanupSessionIDs.insert(sessionID)
            await silentlyDeleteDuplicateSession(
                sessionID: sessionID,
                serverURLString: serverURLString,
                token: token
            )
        }
    }

    private func cleanupProviderBackedSessions(
        serverURLString: String,
        token: String
    ) async {
        let sessionIDs = sessions.compactMap { session -> String? in
            guard SessionUpstreamIdentity(session: session) != nil else { return nil }
            guard !attemptedDuplicateCleanupSessionIDs.contains(session.id) else { return nil }
            return session.id
        }
        guard !sessionIDs.isEmpty else { return }

        for sessionID in sessionIDs {
            attemptedDuplicateCleanupSessionIDs.insert(sessionID)
            await silentlyDeleteDuplicateSession(
                sessionID: sessionID,
                serverURLString: serverURLString,
                token: token
            )
        }
    }

    private func redundantMirroredSessionIDs() -> [String] {
        let groupedSessions = Dictionary(
            grouping: sessions.compactMap { session -> (String, APISession)? in
                guard let key = SessionUpstreamIdentity(session: session)?.key else {
                    return nil
                }
                return (key, session)
            },
            by: \.0
        )

        return groupedSessions.values.flatMap { entries -> [String] in
            let sortedSessions = entries
                .map(\.1)
                .sorted(by: compareMirroredDuplicateSessions)
            guard sortedSessions.count > 1 else { return [] }
            return Array(sortedSessions.dropFirst().map(\.id))
        }
    }

    private func compareMirroredDuplicateSessions(
        _ lhs: APISession,
        _ rhs: APISession
    ) -> Bool {
        if lhs.active != rhs.active {
            return lhs.active && !rhs.active
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
    }

    private func silentlyDeleteDuplicateSession(
        sessionID: String,
        serverURLString: String,
        token: String
    ) async {
        do {
            if let preDeleteKiller {
                try? await preDeleteKiller.killSession(
                    serverURLString: serverURLString,
                    token: token,
                    sessionID: sessionID
                )
            }
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
            messageCacheLRU.removeAll { $0 == sessionID }
            if selectedSessionID == sessionID {
                clearDetailSelectionIfNeeded(sessionID: sessionID)
            }
        } catch {
            // Ignore best-effort cleanup failures to avoid blocking the main session list.
        }
    }

    private func replaceSession(_ session: APISession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        var nextSessions = sessions
        nextSessions[index] = session
        sessions = nextSessions
    }
}

public struct SessionMessagesSnapshot: Equatable, Sendable {
    public let sessionID: String
    public let messages: [APISessionMessage]
    public let errorMessage: String?
    public let sessionMissing: Bool

    public init(
        sessionID: String,
        messages: [APISessionMessage],
        errorMessage: String?,
        sessionMissing: Bool
    ) {
        self.sessionID = sessionID
        self.messages = messages
        self.errorMessage = errorMessage
        self.sessionMissing = sessionMissing
    }
}
