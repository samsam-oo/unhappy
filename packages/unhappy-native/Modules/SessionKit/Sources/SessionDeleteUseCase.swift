import Foundation
import CoreKit

public protocol SessionDeletingAction: Sendable {
    func deleteSession(serverURLString: String, token: String, sessionID: String) async throws
}

public enum SessionDeleteError: LocalizedError, Equatable {
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

public actor SessionDeleteUseCase: SessionDeletingAction {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let sessionID: String
    }

    private let service: any SessionDeleting
    private var inFlightTasks: [RequestKey: Task<Void, Error>] = [:]

    public init(service: any SessionDeleting) {
        self.service = service
    }

    public func deleteSession(serverURLString: String, token: String, sessionID: String) async throws {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw SessionDeleteError.missingToken
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw SessionDeleteError.invalidServerURL
        }

        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionDeleteError.missingSessionID
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
            try await service.deleteSession(
                serverURL: serverURL,
                token: normalizedToken,
                sessionID: normalizedSessionID
            )
        }

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        _ = try await task.value
    }
}
