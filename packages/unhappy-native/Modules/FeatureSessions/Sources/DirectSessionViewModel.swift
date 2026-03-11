import Foundation
import CoreKit
import FeatureNewSession

@MainActor
public final class DirectSessionViewModel: ObservableObject {
    private static let messagePageSize = 240
    private static let incrementalRefreshPageSize = 40
    private static let postSendRefreshDelay: Duration = .milliseconds(250)

    @Published public private(set) var messages: [APISessionMessage] = []
    @Published public private(set) var hasOlderMessages = false
    @Published public private(set) var isLoading = false
    @Published public private(set) var isLoadingOlderMessages = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var liveStatusText: String?
    @Published public private(set) var isSending = false
    @Published public private(set) var sendErrorMessage: String?
    @Published public private(set) var isArchiving = false
    @Published public private(set) var archiveErrorMessage: String?
    @Published public private(set) var availableModelOptions: [NewSessionModelOption] = []
    @Published public private(set) var availableReasoningEfforts: [NewSessionReasoningEffort] = []
    @Published public private(set) var isLoadingCapabilities = false
    @Published public private(set) var capabilitiesErrorMessage: String?
    @Published public var selectedModelOverride: String = ""
    @Published public var selectedReasoningEffortOverride: NewSessionReasoningEffort = .auto
    @Published public var filePathDraft: String = ""
    @Published public private(set) var fileContent: String = ""
    @Published public private(set) var isLoadingFile = false
    @Published public private(set) var fileErrorMessage: String?
    @Published public var reviewRepositoryPathDraft: String = ""
    @Published public private(set) var reviewDiffOutput: String = ""
    @Published public private(set) var reviewStatusMessage: String?
    @Published public private(set) var reviewErrorMessage: String?
    @Published public private(set) var isLoadingReview = false
    @Published public private(set) var worktreeSnapshot: DirectSessionWorktreeSnapshot?
    @Published public private(set) var worktreeErrorMessage: String?
    @Published public private(set) var isLoadingWorktree = false

    public let identity: DirectSessionIdentity

    private let loader: any DirectSessionMessagesLoadingAction
    private let sender: any DirectSessionMessageSendingAction
    private let archiver: (any DirectSessionArchivingAction)?
    private let capabilitiesLoader: (any DirectSessionCapabilitiesLoadingAction)?
    private let fileLoader: (any DirectSessionFileLoadingAction)?
    private let reviewLoader: (any DirectSessionReviewLoadingAction)?
    private let worktreeLoader: (any DirectSessionWorktreeLoadingAction)?
    private var pollingTask: Task<Void, Never>?
    private var postSendRefreshTask: Task<Void, Never>?
    private var activeMessagesLoadTask: Task<APISessionMessagesPage, Error>?
    private var olderMessagesCursor: String?
    private var requestedOlderMessageCursors: Set<String> = []
    private var hasPrependedOlderPages = false

    public var olderMessagesLoadTriggerID: String? {
        guard hasOlderMessages else { return nil }
        guard let olderMessagesCursor else { return nil }
        let trimmed = olderMessagesCursor.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public init(
        identity: DirectSessionIdentity,
        loader: any DirectSessionMessagesLoadingAction,
        sender: any DirectSessionMessageSendingAction,
        archiver: (any DirectSessionArchivingAction)? = nil,
        capabilitiesLoader: (any DirectSessionCapabilitiesLoadingAction)? = nil,
        fileLoader: (any DirectSessionFileLoadingAction)? = nil,
        reviewLoader: (any DirectSessionReviewLoadingAction)? = nil,
        worktreeLoader: (any DirectSessionWorktreeLoadingAction)? = nil
    ) {
        self.identity = identity
        self.loader = loader
        self.sender = sender
        self.archiver = archiver
        self.capabilitiesLoader = capabilitiesLoader
        self.fileLoader = fileLoader
        self.reviewLoader = reviewLoader
        self.worktreeLoader = worktreeLoader
        if let agent = identity.agent {
            self.selectedModelOverride = SessionPreferenceDefaults.defaultModel(for: agent) ?? ""
            self.selectedReasoningEffortOverride =
                SessionPreferenceDefaults.defaultReasoningRawValue(for: agent)
                    .flatMap(NewSessionReasoningEffort.fromBackend) ?? .auto
        }
    }

    deinit {
        pollingTask?.cancel()
        postSendRefreshTask?.cancel()
    }

    public func load(serverURLString: String, token: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await loadMessagesShared(
                serverURLString: serverURLString,
                token: token
            )
            applyLatestPage(page)
            errorMessage = nil
            liveStatusText = nil
        } catch {
            applyMessagesLoadError(error)
        }
    }

    public func loadOlderMessages(serverURLString: String, token: String) async {
        guard !isLoadingOlderMessages else { return }
        guard let olderMessagesCursor, !olderMessagesCursor.isEmpty else {
            hasOlderMessages = false
            return
        }
        guard requestedOlderMessageCursors.contains(olderMessagesCursor) == false else {
            self.olderMessagesCursor = nil
            hasOlderMessages = false
            return
        }

        isLoadingOlderMessages = true
        defer { isLoadingOlderMessages = false }

        do {
            requestedOlderMessageCursors.insert(olderMessagesCursor)
            let page = try await loader.loadMessages(
                serverURLString: serverURLString,
                token: token,
                identity: identity,
                limit: Self.messagePageSize,
                cursor: olderMessagesCursor
            )

            let existingIDs = Set(messages.map(\.id))
            let prepended = page.messages.filter { !existingIDs.contains($0.id) }
            if !prepended.isEmpty {
                messages = prepended + messages
                hasPrependedOlderPages = true
            }
            let nextCursor = page.nextCursor?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedNextCursor = (nextCursor?.isEmpty == true) ? nil : nextCursor
            if let normalizedNextCursor,
               normalizedNextCursor != olderMessagesCursor,
               requestedOlderMessageCursors.contains(normalizedNextCursor) == false {
                self.olderMessagesCursor = normalizedNextCursor
                hasOlderMessages = page.hasNext
            } else {
                self.olderMessagesCursor = nil
                hasOlderMessages = false
            }
            errorMessage = nil
            liveStatusText = nil
        } catch {
            applyMessagesLoadError(error)
        }
    }

    public func startPolling(
        serverURLString: String,
        token: String,
        interval: Duration = .seconds(5)
    ) {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.runPolling(
                serverURLString: serverURLString,
                token: token,
                interval: interval
            )
        }
    }

    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    public func sendMessage(
        _ text: String,
        serverURLString: String,
        token: String,
        permissionMode: APISessionMessagePermissionMode? = nil
    ) async -> Bool {
        guard !isSending else { return false }

        isSending = true
        sendErrorMessage = nil
        defer { isSending = false }

        do {
            _ = try await sender.sendMessage(
                serverURLString: serverURLString,
                token: token,
                identity: identity,
                text: text,
                model: normalizedModelOverride,
                reasoningEffort: selectedReasoningEffortOverride.apiValue,
                permissionMode: permissionMode
            )
            schedulePostSendRefresh(
                serverURLString: serverURLString,
                token: token
            )
            return true
        } catch {
            sendErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    public var canArchiveCurrentSession: Bool {
        identity.provider == .codex && archiver != nil
    }

    public func archiveSession(
        serverURLString: String,
        token: String
    ) async -> Bool {
        guard let archiver else {
            archiveErrorMessage = "Session archiving is unavailable in this build"
            return false
        }
        guard !isArchiving else { return false }

        isArchiving = true
        archiveErrorMessage = nil
        defer { isArchiving = false }

        do {
            try await archiver.archiveSession(
                serverURLString: serverURLString,
                token: token,
                identity: identity
            )
            return true
        } catch {
            archiveErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    public func clearArchiveError() {
        archiveErrorMessage = nil
    }

    public func loadCapabilities(
        serverURLString: String,
        token: String
    ) async {
        guard let capabilitiesLoader else {
            availableModelOptions = []
            availableReasoningEfforts = []
            capabilitiesErrorMessage = nil
            return
        }
        guard !isLoadingCapabilities else { return }

        isLoadingCapabilities = true
        capabilitiesErrorMessage = nil
        defer { isLoadingCapabilities = false }

        do {
            let capabilities = try await capabilitiesLoader.loadCapabilities(
                serverURLString: serverURLString,
                token: token,
                identity: identity
            )
            let nextModelOptions = NewSessionModelOption.fromCapabilities(capabilities)
            let nextReasoningEfforts = normalizeReasoningEfforts(capabilities.reasoningEfforts)
            if availableModelOptions != nextModelOptions {
                availableModelOptions = nextModelOptions
            }
            if availableReasoningEfforts != nextReasoningEfforts {
                availableReasoningEfforts = nextReasoningEfforts
            }
            capabilitiesErrorMessage = nil
        } catch {
            if !availableModelOptions.isEmpty {
                availableModelOptions = []
            }
            if !availableReasoningEfforts.isEmpty {
                availableReasoningEfforts = []
            }
            capabilitiesErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public var selectedModelOption: NewSessionModelOption? {
        let normalizedOverride = normalizedModelOverride
        guard !normalizedOverride.isEmpty else { return nil }
        return availableModelOptions.first(where: { $0.id == normalizedOverride })
    }

    public func prepareFilePath(_ path: String?) {
        guard let path else { return }
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else { return }
        if filePathDraft != normalizedPath {
            filePathDraft = normalizedPath
        }
    }

    public func loadFile(
        serverURLString: String,
        token: String
    ) async {
        guard let fileLoader else {
            fileContent = ""
            fileErrorMessage = "File viewer is unavailable"
            return
        }

        let normalizedPath = filePathDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            fileContent = ""
            fileErrorMessage = DirectSessionUseCaseError.missingPath.errorDescription
            return
        }

        isLoadingFile = true
        fileErrorMessage = nil
        defer { isLoadingFile = false }

        do {
            fileContent = try await fileLoader.loadFile(
                serverURLString: serverURLString,
                token: token,
                identity: identity,
                path: normalizedPath
            )
            fileErrorMessage = nil
        } catch {
            fileContent = ""
            fileErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func loadReview(
        serverURLString: String,
        token: String
    ) async {
        guard let reviewLoader else {
            reviewDiffOutput = ""
            reviewStatusMessage = nil
            reviewErrorMessage = "Review tools are unavailable"
            return
        }
        guard !isLoadingReview else { return }

        isLoadingReview = true
        reviewStatusMessage = nil
        reviewErrorMessage = nil
        defer { isLoadingReview = false }

        do {
            let output = try await reviewLoader.loadReview(
                serverURLString: serverURLString,
                token: token,
                identity: identity,
                repositoryPath: reviewRepositoryPathDraft
            )
            reviewDiffOutput = output.diffText
            reviewStatusMessage = output.statusMessage
            reviewErrorMessage = nil
        } catch {
            reviewDiffOutput = ""
            reviewStatusMessage = nil
            reviewErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func loadWorktree(
        serverURLString: String,
        token: String
    ) async {
        guard let worktreeLoader else {
            worktreeSnapshot = nil
            worktreeErrorMessage = "Worktree tools are unavailable"
            return
        }
        guard !isLoadingWorktree else { return }

        isLoadingWorktree = true
        worktreeErrorMessage = nil
        defer { isLoadingWorktree = false }

        do {
            worktreeSnapshot = try await worktreeLoader.loadWorktreeSnapshot(
                serverURLString: serverURLString,
                token: token,
                identity: identity
            )
            worktreeErrorMessage = nil
        } catch {
            worktreeSnapshot = nil
            worktreeErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var normalizedModelOverride: String {
        selectedModelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runPolling(
        serverURLString: String,
        token: String,
        interval: Duration
    ) async {
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

            let shouldRefresh = DirectSessionPollingStrategy.shouldRefreshLatestMessages(
                hasExistingMessages: messages.isEmpty == false,
                isSending: isSending,
                isLoadingOlderMessages: isLoadingOlderMessages,
                hasPendingPostSendRefresh: postSendRefreshTask != nil,
                hasActiveMessagesLoad: activeMessagesLoadTask != nil
            )
            guard shouldRefresh else { continue }

            do {
                let page = try await loadMessagesShared(
                    serverURLString: serverURLString,
                    token: token,
                    limit: DirectSessionPollingStrategy.refreshLimit(
                        hasExistingMessages: messages.isEmpty == false,
                        defaultPageSize: Self.messagePageSize
                    )
                )
                if messages.isEmpty {
                    applyLatestPage(page)
                } else {
                    applyIncrementalLatestPage(page)
                }
                errorMessage = nil
                liveStatusText = nil
            } catch {
                applyMessagesLoadError(error)
            }
        }

        pollingTask = nil
    }

    private func schedulePostSendRefresh(
        serverURLString: String,
        token: String
    ) {
        postSendRefreshTask?.cancel()
        let refreshLimit = messages.isEmpty
            ? Self.messagePageSize
            : min(Self.incrementalRefreshPageSize, Self.messagePageSize)
        postSendRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.postSendRefreshDelay)
            } catch is CancellationError {
                return
            } catch {
                return
            }

            guard let self else { return }
            await self.refreshLatestMessages(
                serverURLString: serverURLString,
                token: token,
                limit: refreshLimit
            )
        }
    }

    private func setMessagesIfChanged(_ nextMessages: [APISessionMessage]) {
        guard messages != nextMessages else { return }
        messages = nextMessages
    }

    private func applyLatestPage(_ page: APISessionMessagesPage) {
        let latestMessages = page.messages
        let latestIDs = Set(latestMessages.map(\.id))

        if hasPrependedOlderPages {
            let preservedOlderMessages = messages.filter { !latestIDs.contains($0.id) }
            setMessagesIfChanged(preservedOlderMessages + latestMessages)
            if olderMessagesCursor == nil {
                hasOlderMessages = false
            }
            return
        }

        setMessagesIfChanged(latestMessages)
        olderMessagesCursor = page.nextCursor
        hasOlderMessages = page.hasNext
        requestedOlderMessageCursors = []
    }

    private func applyIncrementalLatestPage(_ page: APISessionMessagesPage) {
        guard !messages.isEmpty else {
            applyLatestPage(page)
            return
        }

        let latestMessages = sessionsNormalizeMessageOrder(page.messages)
        let latestIDs = Set(latestMessages.map(\.id))
        let preservedMessages = messages.filter { !latestIDs.contains($0.id) }
        setMessagesIfChanged(
            sessionsNormalizeMessageOrder(preservedMessages + latestMessages)
        )
    }

    private func refreshLatestMessages(
        serverURLString: String,
        token: String,
        limit: Int
    ) async {
        do {
            let page = try await loadMessagesShared(
                serverURLString: serverURLString,
                token: token,
                limit: limit
            )
            applyIncrementalLatestPage(page)
            errorMessage = nil
            liveStatusText = nil
        } catch {
            applyMessagesLoadError(error)
        }

        postSendRefreshTask = nil
    }

    private func loadMessagesShared(
        serverURLString: String,
        token: String,
        limit: Int? = nil
    ) async throws -> APISessionMessagesPage {
        if let activeMessagesLoadTask {
            return try await activeMessagesLoadTask.value
        }

        let boundedLimit = max(1, limit ?? Self.messagePageSize)
        let task = Task {
            try await loader.loadMessages(
                serverURLString: serverURLString,
                token: token,
                identity: identity,
                limit: boundedLimit,
                cursor: nil
            )
        }
        activeMessagesLoadTask = task

        defer {
            activeMessagesLoadTask = nil
        }

        return try await task.value
    }

    private func applyMessagesLoadError(_ error: Error) {
        if let reconnectingStatusText = MachinesAPIError.reconnectingStatusText(from: error) {
            liveStatusText = reconnectingStatusText
            errorMessage = nil
            return
        }
        liveStatusText = nil
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

private func normalizeReasoningEfforts(_ rawValues: [String]) -> [NewSessionReasoningEffort] {
    var normalized: [NewSessionReasoningEffort] = []
    var seen: Set<NewSessionReasoningEffort> = []

    for raw in rawValues {
        guard let value = NewSessionReasoningEffort.fromBackend(raw) else { continue }
        guard value != .auto else { continue }
        if seen.insert(value).inserted {
            normalized.append(value)
        }
    }

    return normalized
}
