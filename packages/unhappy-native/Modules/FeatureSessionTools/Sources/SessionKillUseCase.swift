import Foundation
import CoreKit

public protocol SessionKillAction: Sendable {
    func killSession(
        serverURLString: String,
        token: String,
        sessionID: String
    ) async throws -> APISessionKillResult
}

public enum SessionKillError: LocalizedError, Equatable {
    case missingToken
    case invalidServerURL
    case missingSessionID
    case failed(message: String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .invalidServerURL:
            return "Invalid server URL"
        case .missingSessionID:
            return "Session ID is required"
        case .failed(let message):
            return message
        }
    }
}

public actor SessionKillUseCase: SessionKillAction {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let sessionID: String
    }

    private let service: any SessionKilling
    private var inFlightTasks: [RequestKey: Task<APISessionKillResult, Error>] = [:]

    public init(service: any SessionKilling) {
        self.service = service
    }

    public func killSession(
        serverURLString: String,
        token: String,
        sessionID: String
    ) async throws -> APISessionKillResult {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw SessionKillError.missingToken
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw SessionKillError.invalidServerURL
        }

        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionKillError.missingSessionID
        }

        let key = RequestKey(
            serverURLString: normalizedURL,
            token: normalizedToken,
            sessionID: normalizedSessionID
        )

        if let inFlightTask = inFlightTasks[key] {
            return try await inFlightTask.value
        }

        let service = self.service
        let task = Task<APISessionKillResult, Error> {
            let result = try await service.killSession(
                serverURL: serverURL,
                token: normalizedToken,
                sessionID: normalizedSessionID
            )

            if result.success {
                return result
            }

            throw SessionKillError.failed(message: result.message)
        }

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        return try await task.value
    }
}
