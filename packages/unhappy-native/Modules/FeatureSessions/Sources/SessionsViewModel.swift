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
    @Published public private(set) var selectedClaudeSessions: [APIClaudeSessionSummary] = []
    @Published public private(set) var isLoadingClaudeSessions = false
    @Published public private(set) var selectedClaudeSessionsErrorMessage: String?
    @Published public private(set) var selectedClaudeSessionsSessionID: String?
    @Published public private(set) var claudeResumeInProgressSessionID: String?
    @Published public private(set) var claudeResumeStatusMessage: String?
    @Published public private(set) var claudeResumeErrorMessage: String?
    @Published public private(set) var deletingSessionIDs: Set<String> = []
    @Published public private(set) var renamingSessionIDs: Set<String> = []

    private let loader: any SessionsLoading
    private let pageLoader: any SessionsPageLoading
    private let poller: any SessionsPolling
    private let messageLoader: any SessionsMessagesLoading
    private let codexThreadsLoader: (any SessionCodexThreadsLoading)?
    private let claudeSessionsLoader: (any SessionClaudeSessionsLoading)?
    private let spawnUseCase: (any SessionSpawningAction)?
    private let deleteUseCase: any SessionDeletingAction
    private let titleUseCase: any SessionTitleUpdatingAction
    private var messagesBySessionID: [String: [APISessionMessage]] = [:]
    private var messageCacheLRU: [String] = []
    private var nextCursor: String?

    public init(
        loader: any SessionsLoading,
        pageLoader: any SessionsPageLoading,
        poller: any SessionsPolling,
        messageLoader: any SessionsMessagesLoading,
        codexThreadsLoader: (any SessionCodexThreadsLoading)? = nil,
        claudeSessionsLoader: (any SessionClaudeSessionsLoading)? = nil,
        spawnUseCase: (any SessionSpawningAction)? = nil,
        deleteUseCase: any SessionDeletingAction,
        titleUseCase: any SessionTitleUpdatingAction
    ) {
        self.loader = loader
        self.pageLoader = pageLoader
        self.poller = poller
        self.messageLoader = messageLoader
        self.codexThreadsLoader = codexThreadsLoader
        self.claudeSessionsLoader = claudeSessionsLoader
        self.spawnUseCase = spawnUseCase
        self.deleteUseCase = deleteUseCase
        self.titleUseCase = titleUseCase
    }

    public convenience init(
        service: any SessionsFetching & SessionsPagingFetching & SessionMessagesFetching & SessionDeleting & SessionTitleUpdating & SessionCodexThreadsFetching & SessionClaudeSessionsFetching & SessionSpawning
    ) {
        let loader = SessionsLoadUseCase(service: service)
        self.init(
            loader: loader,
            pageLoader: SessionsPageLoadUseCase(service: service),
            poller: SessionsPollingUseCase(loader: loader),
            messageLoader: SessionMessagesLoadUseCase(service: service),
            codexThreadsLoader: SessionCodexThreadsLoadUseCase(service: service),
            claudeSessionsLoader: SessionClaudeSessionsLoadUseCase(service: service),
            spawnUseCase: SessionSpawnUseCase(service: service),
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

    var cachedSessionMessagesCount: Int {
        messagesBySessionID.count
    }

    public func isDeleting(sessionID: String) -> Bool {
        deletingSessionIDs.contains(sessionID)
    }

    public func isRenaming(sessionID: String) -> Bool {
        renamingSessionIDs.contains(sessionID)
    }

    public func load(serverURLString: String, token: String) async {
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
                errorMessage = nil
                isLoading = false
            }
        } catch is CancellationError {
            // Stream cancellation is expected when the view task is torn down.
        } catch {
            sessions = []
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
            self.nextCursor = page.nextCursor
            hasMoreSessions = page.hasNext
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func loadMessages(for sessionID: String, serverURLString: String, token: String) async {
        selectedSessionID = sessionID
        selectedSessionErrorMessage = nil
        isLoadingSessionMessages = true

        if let cachedMessages = messagesBySessionID[sessionID] {
            selectedSessionMessages = cachedMessages
        } else {
            selectedSessionMessages = []
        }

        defer {
            isLoadingSessionMessages = false
        }

        do {
            let messages = try await messageLoader.loadMessages(
                serverURLString: serverURLString,
                token: token,
                sessionID: sessionID
            )
            cacheMessages(messages, for: sessionID)
            if selectedSessionID == sessionID {
                selectedSessionMessages = messagesBySessionID[sessionID] ?? messages
                selectedSessionErrorMessage = nil
            }
        } catch {
            if selectedSessionID == sessionID {
                selectedSessionMessages = []
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

    public func deleteSession(sessionID: String, serverURLString: String, token: String) async {
        deletingSessionIDs.insert(sessionID)
        defer { deletingSessionIDs.remove(sessionID) }

        do {
            try await deleteUseCase.deleteSession(
                serverURLString: serverURLString,
                token: token,
                sessionID: sessionID
            )

            sessions.removeAll { $0.id == sessionID }
            messagesBySessionID[sessionID] = nil
            if selectedSessionID == sessionID {
                selectedSessionID = nil
                selectedSessionMessages = []
                selectedSessionErrorMessage = nil
            }
            messageCacheLRU.removeAll { $0 == sessionID }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func clearDetailSelectionIfNeeded(sessionID: String) {
        guard selectedSessionID == sessionID else { return }
        selectedSessionID = nil
        selectedSessionMessages = []
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
        claudeResumeInProgressSessionID = nil
        claudeResumeStatusMessage = nil
        claudeResumeErrorMessage = nil
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
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func cacheMessages(_ messages: [APISessionMessage], for sessionID: String) {
        let normalizedMessages: [APISessionMessage]
        if messages.count > CachePolicy.maxMessagesPerSession {
            normalizedMessages = Array(messages.suffix(CachePolicy.maxMessagesPerSession))
        } else {
            normalizedMessages = messages
        }

        messagesBySessionID[sessionID] = normalizedMessages
        touchCache(sessionID: sessionID)
        evictCacheIfNeeded(preserving: selectedSessionID)
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
