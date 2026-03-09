import Foundation
import CoreKit
import FeatureNewSession

@MainActor
public final class DirectSessionViewModel: ObservableObject {
    @Published public private(set) var messages: [APISessionMessage] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isSending = false
    @Published public private(set) var sendErrorMessage: String?
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
    private let capabilitiesLoader: (any DirectSessionCapabilitiesLoadingAction)?
    private let fileLoader: (any DirectSessionFileLoadingAction)?
    private let reviewLoader: (any DirectSessionReviewLoadingAction)?
    private let worktreeLoader: (any DirectSessionWorktreeLoadingAction)?
    private var pollingTask: Task<Void, Never>?

    public init(
        identity: DirectSessionIdentity,
        loader: any DirectSessionMessagesLoadingAction,
        sender: any DirectSessionMessageSendingAction,
        capabilitiesLoader: (any DirectSessionCapabilitiesLoadingAction)? = nil,
        fileLoader: (any DirectSessionFileLoadingAction)? = nil,
        reviewLoader: (any DirectSessionReviewLoadingAction)? = nil,
        worktreeLoader: (any DirectSessionWorktreeLoadingAction)? = nil
    ) {
        self.identity = identity
        self.loader = loader
        self.sender = sender
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
    }

    public func load(serverURLString: String, token: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            messages = try await loader.loadMessages(
                serverURLString: serverURLString,
                token: token,
                identity: identity
            )
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
            await load(serverURLString: serverURLString, token: token)
            return true
        } catch {
            sendErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
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
            availableModelOptions = NewSessionModelOption.fromCapabilities(capabilities)
            availableReasoningEfforts = normalizeReasoningEfforts(capabilities.reasoningEfforts)
            capabilitiesErrorMessage = nil
        } catch {
            availableModelOptions = []
            availableReasoningEfforts = []
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

            do {
                messages = try await loader.loadMessages(
                    serverURLString: serverURLString,
                    token: token,
                    identity: identity
                )
                errorMessage = nil
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }

        pollingTask = nil
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
