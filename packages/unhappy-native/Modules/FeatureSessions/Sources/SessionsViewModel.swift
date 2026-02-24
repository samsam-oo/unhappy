import Foundation
import CoreKit

@MainActor
public final class SessionsViewModel: ObservableObject {
    @Published public private(set) var sessions: [APISession] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?

    private let service: SessionsFetching

    public init(service: SessionsFetching = URLSessionSessionsService()) {
        self.service = service
    }

    public var multiAgentInProgress: Bool {
        if isLoading {
            return true
        }
        return sessions.contains(where: { $0.active })
    }

    public func load(serverURLString: String, token: String) async {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            sessions = []
            errorMessage = "API token is required"
            return
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let serverURL = URL(string: normalizedURL), !normalizedURL.isEmpty else {
            sessions = []
            errorMessage = "Invalid server URL"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let rows = try await service.fetchSessions(serverURL: serverURL, token: normalizedToken)
            sessions = rows.sorted { $0.updatedAt > $1.updatedAt }
            errorMessage = nil
        } catch {
            sessions = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
