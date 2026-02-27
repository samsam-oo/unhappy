import Foundation
import CoreKit

public protocol SessionModelsLoadingAction: Sendable {
    func loadSessionModels(
        serverURLString: String,
        token: String,
        sessionID: String,
        agent: APISessionSpawnAgent?
    ) async throws -> APIMachineAgentCapabilities
}

public enum SessionModelsLoadingError: LocalizedError, Equatable {
    case missingToken
    case invalidServerURL
    case missingSessionID

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .invalidServerURL:
            return "Invalid server URL"
        case .missingSessionID:
            return "Session ID is required"
        }
    }
}

public actor SessionModelsLoadUseCase: SessionModelsLoadingAction {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let sessionID: String
        let agent: APISessionSpawnAgent?
    }

    private let service: any SessionModelsListing
    private var inFlightTasks: [RequestKey: Task<APIMachineAgentCapabilities, Error>] = [:]

    public init(service: any SessionModelsListing) {
        self.service = service
    }

    public func loadSessionModels(
        serverURLString: String,
        token: String,
        sessionID: String,
        agent: APISessionSpawnAgent?
    ) async throws -> APIMachineAgentCapabilities {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw SessionModelsLoadingError.missingToken
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw SessionModelsLoadingError.invalidServerURL
        }

        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionModelsLoadingError.missingSessionID
        }

        let key = RequestKey(
            serverURLString: normalizedURL,
            token: normalizedToken,
            sessionID: normalizedSessionID,
            agent: agent
        )

        if let inFlightTask = inFlightTasks[key] {
            return try await inFlightTask.value
        }

        let service = self.service
        let task = Task<APIMachineAgentCapabilities, Error> {
            try await service.fetchAgentCapabilities(
                serverURL: serverURL,
                token: normalizedToken,
                sessionID: normalizedSessionID,
                agent: agent
            )
        }

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        return try await task.value
    }
}
