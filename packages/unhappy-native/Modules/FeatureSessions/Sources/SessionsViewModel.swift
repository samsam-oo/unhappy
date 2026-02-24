import Foundation
import CoreKit

@MainActor
public final class SessionsViewModel: ObservableObject {
    @Published public private(set) var sessions: [APISession] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?

    private let loader: any SessionsLoading
    private let poller: any SessionsPolling

    public init(loader: any SessionsLoading, poller: any SessionsPolling) {
        self.loader = loader
        self.poller = poller
    }

    public convenience init(service: any SessionsFetching) {
        let loader = SessionsLoadUseCase(service: service)
        self.init(
            loader: loader,
            poller: SessionsPollingUseCase(loader: loader)
        )
    }

    public var multiAgentInProgress: Bool {
        if isLoading {
            return true
        }
        return sessions.contains(where: { $0.active })
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
}
