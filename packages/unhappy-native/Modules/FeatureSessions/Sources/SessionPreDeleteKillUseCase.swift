import Foundation
import CoreKit

public protocol SessionPreDeleteKillingAction: Sendable {
    func killSession(
        serverURLString: String,
        token: String,
        sessionID: String
    ) async throws
}

public enum SessionPreDeleteKillError: LocalizedError, Equatable {
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

public actor SessionPreDeleteKillUseCase: SessionPreDeleteKillingAction {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let sessionID: String
    }

    private let service: any SessionKilling
    private var inFlightTasks: [RequestKey: Task<Void, Error>] = [:]

    public init(service: any SessionKilling) {
        self.service = service
    }

    public func killSession(
        serverURLString: String,
        token: String,
        sessionID: String
    ) async throws {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw SessionPreDeleteKillError.missingToken
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw SessionPreDeleteKillError.invalidServerURL
        }

        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionPreDeleteKillError.missingSessionID
        }

        let key = RequestKey(
            serverURLString: normalizedURL,
            token: normalizedToken,
            sessionID: normalizedSessionID
        )
        if let inFlightTask = inFlightTasks[key] {
            _ = try await inFlightTask.value
            return
        }

        let service = self.service
        let task = Task<Void, Error> {
            let result = try await service.killSession(
                serverURL: serverURL,
                token: normalizedToken,
                sessionID: normalizedSessionID
            )
            if result.success {
                return
            }
            throw SessionPreDeleteKillError.failed(message: result.message)
        }

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        _ = try await task.value
    }
}
