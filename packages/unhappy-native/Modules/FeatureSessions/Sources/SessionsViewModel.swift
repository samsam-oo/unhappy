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
    @Published public private(set) var selectedSessionID: String?
    @Published public private(set) var selectedSessionMessages: [APISessionMessage] = []
    @Published public private(set) var isLoadingSessionMessages = false
    @Published public private(set) var selectedSessionErrorMessage: String?
    @Published public private(set) var deletingSessionIDs: Set<String> = []

    private let loader: any SessionsLoading
    private let poller: any SessionsPolling
    private let messageLoader: any SessionsMessagesLoading
    private let deleteUseCase: any SessionDeletingAction
    private var messagesBySessionID: [String: [APISessionMessage]] = [:]
    private var messageCacheLRU: [String] = []

    public init(
        loader: any SessionsLoading,
        poller: any SessionsPolling,
        messageLoader: any SessionsMessagesLoading,
        deleteUseCase: any SessionDeletingAction
    ) {
        self.loader = loader
        self.poller = poller
        self.messageLoader = messageLoader
        self.deleteUseCase = deleteUseCase
    }

    public convenience init(
        service: any SessionsFetching & SessionMessagesFetching & SessionDeleting
    ) {
        let loader = SessionsLoadUseCase(service: service)
        self.init(
            loader: loader,
            poller: SessionsPollingUseCase(loader: loader),
            messageLoader: SessionMessagesLoadUseCase(service: service),
            deleteUseCase: SessionDeleteUseCase(service: service)
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

    public func isDeleting(sessionID: String) -> Bool {
        deletingSessionIDs.contains(sessionID)
    }

    public func load(serverURLString: String, token: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            sessions = try await loader.loadSessions(serverURLString: serverURLString, token: token)
            errorMessage = nil
        } catch {
            sessions = []
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
                sessions = rows
                errorMessage = nil
                isLoading = false
            }
        } catch is CancellationError {
            // Stream cancellation is expected when the view task is torn down.
        } catch {
            sessions = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isLoading = false
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
}
