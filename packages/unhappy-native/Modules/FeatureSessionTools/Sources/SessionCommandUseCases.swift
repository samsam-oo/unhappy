import Foundation
import CoreKit

public protocol SessionTaskAbortAction: Sendable {
    func abortTask(
        serverURLString: String,
        token: String,
        sessionID: String,
        reason: String?
    ) async throws -> APISessionCommandResult
}

public protocol SessionPermissionResponseAction: Sendable {
    func respondPermission(
        serverURLString: String,
        token: String,
        sessionID: String,
        permissionRequestID: String,
        approved: Bool,
        mode: APISessionPermissionMode?,
        allowTools: [String]?,
        decision: APISessionPermissionDecision?
    ) async throws -> APISessionCommandResult
}

public protocol SessionModeSwitchAction: Sendable {
    func switchMode(
        serverURLString: String,
        token: String,
        sessionID: String,
        to: APISessionSwitchTarget
    ) async throws -> APISessionSwitchResult
}

public enum SessionCommandError: LocalizedError, Equatable {
    case missingToken
    case invalidServerURL
    case missingSessionID
    case missingPermissionRequestID
    case failed(message: String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .invalidServerURL:
            return "Invalid server URL"
        case .missingSessionID:
            return "Session ID is required"
        case .missingPermissionRequestID:
            return "Permission request ID is required"
        case .failed(let message):
            return message
        }
    }
}

public actor SessionTaskAbortUseCase: SessionTaskAbortAction {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let sessionID: String
        let reason: String?
    }

    private let service: any SessionAborting
    private var inFlightTasks: [RequestKey: Task<APISessionCommandResult, Error>] = [:]

    public init(service: any SessionAborting) {
        self.service = service
    }

    public func abortTask(
        serverURLString: String,
        token: String,
        sessionID: String,
        reason: String?
    ) async throws -> APISessionCommandResult {
        let (serverURL, normalizedToken, normalizedSessionID) = try normalizeSessionInputs(
            serverURLString: serverURLString,
            token: token,
            sessionID: sessionID
        )
        let normalizedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = RequestKey(
            serverURLString: serverURL.absoluteString,
            token: normalizedToken,
            sessionID: normalizedSessionID,
            reason: normalizedReason
        )

        if let inFlightTask = inFlightTasks[key] {
            return try await inFlightTask.value
        }

        let service = self.service
        let task = Task<APISessionCommandResult, Error> {
            let result = try await service.abortSessionTask(
                serverURL: serverURL,
                token: normalizedToken,
                sessionID: normalizedSessionID,
                reason: normalizedReason
            )
            if result.success {
                return result
            }
            let normalizedError = result.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SessionCommandError.failed(
                message: (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "Failed to abort session task"
            )
        }

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        return try await task.value
    }
}

public actor SessionPermissionUseCase: SessionPermissionResponseAction {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let sessionID: String
        let permissionRequestID: String
        let approved: Bool
        let mode: APISessionPermissionMode?
        let allowTools: [String]?
        let decision: APISessionPermissionDecision?
    }

    private let service: any SessionPermissionResponding
    private var inFlightTasks: [RequestKey: Task<APISessionCommandResult, Error>] = [:]

    public init(service: any SessionPermissionResponding) {
        self.service = service
    }

    public func respondPermission(
        serverURLString: String,
        token: String,
        sessionID: String,
        permissionRequestID: String,
        approved: Bool,
        mode: APISessionPermissionMode?,
        allowTools: [String]?,
        decision: APISessionPermissionDecision?
    ) async throws -> APISessionCommandResult {
        let (serverURL, normalizedToken, normalizedSessionID) = try normalizeSessionInputs(
            serverURLString: serverURLString,
            token: token,
            sessionID: sessionID
        )
        let normalizedPermissionRequestID = permissionRequestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPermissionRequestID.isEmpty else {
            throw SessionCommandError.missingPermissionRequestID
        }
        let normalizedAllowTools = allowTools?.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let key = RequestKey(
            serverURLString: serverURL.absoluteString,
            token: normalizedToken,
            sessionID: normalizedSessionID,
            permissionRequestID: normalizedPermissionRequestID,
            approved: approved,
            mode: mode,
            allowTools: normalizedAllowTools,
            decision: decision
        )
        if let inFlightTask = inFlightTasks[key] {
            return try await inFlightTask.value
        }

        let service = self.service
        let task = Task<APISessionCommandResult, Error> {
            let result = try await service.respondPermission(
                serverURL: serverURL,
                token: normalizedToken,
                sessionID: normalizedSessionID,
                permissionRequestID: normalizedPermissionRequestID,
                approved: approved,
                mode: mode,
                allowTools: normalizedAllowTools,
                decision: decision
            )
            if result.success {
                return result
            }
            let normalizedError = result.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SessionCommandError.failed(
                message: (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "Failed to respond to permission"
            )
        }

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        return try await task.value
    }
}

public actor SessionModeSwitchUseCase: SessionModeSwitchAction {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let sessionID: String
        let to: APISessionSwitchTarget
    }

    private let service: any SessionModeSwitching
    private var inFlightTasks: [RequestKey: Task<APISessionSwitchResult, Error>] = [:]

    public init(service: any SessionModeSwitching) {
        self.service = service
    }

    public func switchMode(
        serverURLString: String,
        token: String,
        sessionID: String,
        to: APISessionSwitchTarget
    ) async throws -> APISessionSwitchResult {
        let (serverURL, normalizedToken, normalizedSessionID) = try normalizeSessionInputs(
            serverURLString: serverURLString,
            token: token,
            sessionID: sessionID
        )
        let key = RequestKey(
            serverURLString: serverURL.absoluteString,
            token: normalizedToken,
            sessionID: normalizedSessionID,
            to: to
        )
        if let inFlightTask = inFlightTasks[key] {
            return try await inFlightTask.value
        }

        let service = self.service
        let task = Task<APISessionSwitchResult, Error> {
            let result = try await service.switchSessionMode(
                serverURL: serverURL,
                token: normalizedToken,
                sessionID: normalizedSessionID,
                to: to
            )
            if result.success {
                return result
            }
            let normalizedError = result.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SessionCommandError.failed(
                message: (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "Failed to switch session mode"
            )
        }

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        return try await task.value
    }
}

private func normalizeSessionInputs(
    serverURLString: String,
    token: String,
    sessionID: String
) throws -> (URL, String, String) {
    let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedToken.isEmpty else {
        throw SessionCommandError.missingToken
    }

    let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
        !normalizedURL.isEmpty,
        let serverURL = URL(string: normalizedURL),
        serverURL.scheme != nil,
        serverURL.host != nil
    else {
        throw SessionCommandError.invalidServerURL
    }

    let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedSessionID.isEmpty else {
        throw SessionCommandError.missingSessionID
    }

    return (serverURL, normalizedToken, normalizedSessionID)
}
