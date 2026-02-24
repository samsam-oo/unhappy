import Foundation
import CoreKit

@MainActor
public final class SessionsViewModel: ObservableObject {
    @Published public private(set) var sessions: [APISession] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?

    private let loader: any SessionsLoading

    public init(loader: any SessionsLoading) {
        self.loader = loader
    }

    public convenience init(service: any SessionsFetching) {
        self.init(loader: SessionsLoadUseCase(service: service))
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
}
