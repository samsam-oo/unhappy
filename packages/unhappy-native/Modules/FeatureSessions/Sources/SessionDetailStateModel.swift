import Foundation
import CoreKit

@MainActor
final class SessionDetailStateModel: ObservableObject {
    @Published private(set) var messages: [APISessionMessage]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let sessionID: String
    private let serverURLString: String
    private let token: String
    private unowned let sessionsViewModel: SessionsViewModel
    private var pollingTask: Task<Void, Never>?

    init(
        sessionID: String,
        sessionsViewModel: SessionsViewModel,
        serverURLString: String,
        token: String
    ) {
        self.sessionID = sessionID
        self.sessionsViewModel = sessionsViewModel
        self.serverURLString = serverURLString
        self.token = token
        self.messages = sessionsViewModel.messages(for: sessionID)
    }

    deinit {
        pollingTask?.cancel()
    }

    func startPolling(interval: Duration = .seconds(5)) {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.runPolling(interval: interval)
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func syncFromCache() {
        messages = sessionsViewModel.messages(for: sessionID)
    }

    @discardableResult
    func loadMessages(
        showsLoadingState: Bool = true,
        clearsMessagesOnFailure: Bool = true
    ) async -> SessionMessagesSnapshot {
        if showsLoadingState {
            isLoading = true
        }
        defer {
            if showsLoadingState {
                isLoading = false
            }
        }

        let snapshot = await sessionsViewModel.refreshMessagesSnapshot(
            for: sessionID,
            serverURLString: serverURLString,
            token: token,
            clearsMessagesOnFailure: clearsMessagesOnFailure
        )

        if Task.isCancelled {
            return snapshot
        }

        messages = snapshot.messages
        errorMessage = snapshot.errorMessage
        return snapshot
    }

    private func runPolling(interval: Duration) async {
        _ = await loadMessages(showsLoadingState: true, clearsMessagesOnFailure: true)

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

            _ = await loadMessages(
                showsLoadingState: false,
                clearsMessagesOnFailure: false
            )
        }

        pollingTask = nil
    }
}
