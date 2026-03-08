import Foundation
import CoreKit

@MainActor
public final class CodexDirectSessionViewModel: ObservableObject {
    @Published public private(set) var messages: [APISessionMessage] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isSending = false
    @Published public private(set) var sendErrorMessage: String?

    public let identity: CodexDirectSessionIdentity

    private let loader: any CodexDirectSessionMessagesLoadingAction
    private let sender: any CodexDirectSessionMessageSendingAction
    private var pollingTask: Task<Void, Never>?

    public init(
        identity: CodexDirectSessionIdentity,
        loader: any CodexDirectSessionMessagesLoadingAction,
        sender: any CodexDirectSessionMessageSendingAction
    ) {
        self.identity = identity
        self.loader = loader
        self.sender = sender
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
        token: String
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
                text: text
            )
            await load(serverURLString: serverURLString, token: token)
            return true
        } catch {
            sendErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
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
