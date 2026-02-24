import Foundation
import CoreKit

public protocol SessionTitleUpdatingAction: Sendable {
    func setSessionTitle(
        serverURLString: String,
        token: String,
        sessionID: String,
        title: String?
    ) async throws
}

public enum SessionTitleUpdateError: LocalizedError, Equatable {
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

public actor SessionTitleUpdateUseCase: SessionTitleUpdatingAction {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let sessionID: String
        let title: String?
    }

    private let service: any SessionTitleUpdating
    private var inFlightTasks: [RequestKey: Task<Void, Error>] = [:]

    public init(service: any SessionTitleUpdating) {
        self.service = service
    }

    public func setSessionTitle(
        serverURLString: String,
        token: String,
        sessionID: String,
        title: String?
    ) async throws {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw SessionTitleUpdateError.missingToken
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw SessionTitleUpdateError.invalidServerURL
        }

        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionTitleUpdateError.missingSessionID
        }

        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = RequestKey(
            serverURLString: normalizedURL,
            token: normalizedToken,
            sessionID: normalizedSessionID,
            title: normalizedTitle?.isEmpty == true ? nil : normalizedTitle
        )

        if let inFlightTask = inFlightTasks[key] {
            _ = try await inFlightTask.value
            return
        }

        let service = self.service
        let task = Task<Void, Error> {
            try await service.setSessionTitle(
                serverURL: serverURL,
                token: normalizedToken,
                sessionID: normalizedSessionID,
                title: key.title
            )
        }

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        _ = try await task.value
    }
}
