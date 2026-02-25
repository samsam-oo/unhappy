import Foundation

public enum HomeServerConnectionStatus: Equatable, Sendable {
    case connecting
    case connected
    case disconnected
}

public protocol HomeServerHealthChecking: Sendable {
    func checkReachable(serverURL: URL) async throws -> Bool
}

public actor HomeServerHealthCheckService: HomeServerHealthChecking {
    private let urlSession: URLSession
    private let timeoutInterval: TimeInterval

    public init(
        urlSession: URLSession = .shared,
        timeoutInterval: TimeInterval = 5
    ) {
        self.urlSession = urlSession
        self.timeoutInterval = timeoutInterval
    }

    public func checkReachable(serverURL: URL) async throws -> Bool {
        var request = URLRequest(url: serverURL.appending(path: "v1/sessions"))
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval

        let (_, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        return httpResponse.statusCode < 500
    }
}

public protocol HomeServerConnectionStatusLoadingAction: Sendable {
    func loadStatus(serverURLString: String) async -> HomeServerConnectionStatus
}

public actor HomeServerConnectionStatusLoadUseCase: HomeServerConnectionStatusLoadingAction {
    private let healthChecker: any HomeServerHealthChecking

    public init(healthChecker: any HomeServerHealthChecking = HomeServerHealthCheckService()) {
        self.healthChecker = healthChecker
    }

    public func loadStatus(serverURLString: String) async -> HomeServerConnectionStatus {
        let normalizedURLString = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURLString.isEmpty,
            let serverURL = URL(string: normalizedURLString),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            return .disconnected
        }

        do {
            let reachable = try await healthChecker.checkReachable(serverURL: serverURL)
            return reachable ? .connected : .disconnected
        } catch {
            return .disconnected
        }
    }
}
