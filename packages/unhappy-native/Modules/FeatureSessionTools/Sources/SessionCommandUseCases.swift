import Foundation
import CoreKit

public protocol SessionTaskAbortAction: Sendable {
    func abortTask(_ request: SessionAbortTaskRequest) async throws -> APISessionCommandResult
}

public protocol SessionPermissionResponseAction: Sendable {
    func respondPermission(_ request: SessionPermissionResponseRequest) async throws -> APISessionCommandResult
}

public protocol SessionModeSwitchAction: Sendable {
    func switchMode(_ request: SessionModeSwitchRequest) async throws -> APISessionSwitchResult
}

public protocol SessionBashRunAction: Sendable {
    func runBash(_ request: SessionBashCommandRequest) async throws -> APISessionBashResult
}

public protocol SessionRipgrepRunAction: Sendable {
    func runRipgrep(_ request: SessionArgumentCommandRequest) async throws -> APISessionBashResult
}

public protocol SessionDifftasticRunAction: Sendable {
    func runDifftastic(_ request: SessionArgumentCommandRequest) async throws -> APISessionBashResult
}

public struct SessionAbortTaskRequest: Sendable, Equatable {
    public let serverURLString: String
    public let token: String
    public let sessionID: String
    public let reason: String?
}

public struct SessionPermissionResponseRequest: Sendable, Equatable {
    public let serverURLString: String
    public let token: String
    public let sessionID: String
    public let permissionRequestID: String
    public let approved: Bool
    public let mode: APISessionPermissionMode?
    public let allowTools: [String]?
    public let decision: APISessionPermissionDecision?
}

public struct SessionModeSwitchRequest: Sendable, Equatable {
    public let serverURLString: String
    public let token: String
    public let sessionID: String
    public let targetMode: APISessionSwitchTarget
}

public struct SessionBashCommandRequest: Sendable, Equatable {
    public let serverURLString: String
    public let token: String
    public let sessionID: String
    public let command: String
    public let cwd: String?
    public let timeout: Int?
}

public struct SessionArgumentCommandRequest: Sendable, Equatable {
    public let serverURLString: String
    public let token: String
    public let sessionID: String
    public let arguments: [String]
    public let cwd: String?
}

public enum SessionCommandError: LocalizedError, Equatable {
    case missingToken
    case invalidServerURL
    case missingSessionID
    case missingPermissionRequestID
    case missingCommand
    case missingArguments
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
        case .missingCommand:
            return "Command is required"
        case .missingArguments:
            return "At least one argument is required"
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

    public func abortTask(_ request: SessionAbortTaskRequest) async throws -> APISessionCommandResult {
        let (serverURL, normalizedToken, normalizedSessionID) = try normalizeSessionInputs(
            serverURLString: request.serverURLString,
            token: request.token,
            sessionID: request.sessionID
        )
        let normalizedReason = request.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
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

    public func respondPermission(_ request: SessionPermissionResponseRequest) async throws -> APISessionCommandResult {
        let (serverURL, normalizedToken, normalizedSessionID) = try normalizeSessionInputs(
            serverURLString: request.serverURLString,
            token: request.token,
            sessionID: request.sessionID
        )
        let normalizedPermissionRequestID = request.permissionRequestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPermissionRequestID.isEmpty else {
            throw SessionCommandError.missingPermissionRequestID
        }
        let normalizedAllowTools = request.allowTools?.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let key = RequestKey(
            serverURLString: serverURL.absoluteString,
            token: normalizedToken,
            sessionID: normalizedSessionID,
            permissionRequestID: normalizedPermissionRequestID,
            approved: request.approved,
            mode: request.mode,
            allowTools: normalizedAllowTools,
            decision: request.decision
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
                approved: request.approved,
                mode: request.mode,
                allowTools: normalizedAllowTools,
                decision: request.decision
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

    public func switchMode(_ request: SessionModeSwitchRequest) async throws -> APISessionSwitchResult {
        let (serverURL, normalizedToken, normalizedSessionID) = try normalizeSessionInputs(
            serverURLString: request.serverURLString,
            token: request.token,
            sessionID: request.sessionID
        )
        let key = RequestKey(
            serverURLString: serverURL.absoluteString,
            token: normalizedToken,
            sessionID: normalizedSessionID,
            to: request.targetMode
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
                to: request.targetMode
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

public actor SessionBashUseCase: SessionBashRunAction {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let sessionID: String
        let command: String
        let cwd: String?
        let timeout: Int?
    }

    private let service: any SessionBashRunning
    private var inFlightTasks: [RequestKey: Task<APISessionBashResult, Error>] = [:]

    public init(service: any SessionBashRunning) {
        self.service = service
    }

    public func runBash(_ request: SessionBashCommandRequest) async throws -> APISessionBashResult {
        let (serverURL, normalizedToken, normalizedSessionID) = try normalizeSessionInputs(
            serverURLString: request.serverURLString,
            token: request.token,
            sessionID: request.sessionID
        )
        let normalizedCommand = request.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCommand.isEmpty else {
            throw SessionCommandError.missingCommand
        }
        let normalizedCWD = request.cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = RequestKey(
            serverURLString: serverURL.absoluteString,
            token: normalizedToken,
            sessionID: normalizedSessionID,
            command: normalizedCommand,
            cwd: normalizedCWD,
            timeout: request.timeout
        )
        if let inFlightTask = inFlightTasks[key] {
            return try await inFlightTask.value
        }

        let service = self.service
        let task = Task<APISessionBashResult, Error> {
            let result = try await service.runBash(
                serverURL: serverURL,
                token: normalizedToken,
                sessionID: normalizedSessionID,
                command: normalizedCommand,
                cwd: normalizedCWD,
                timeout: request.timeout
            )
            if result.success {
                return result
            }
            let normalizedError = result.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SessionCommandError.failed(
                message: (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "Failed to run bash command"
            )
        }

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        return try await task.value
    }
}

public actor SessionRipgrepUseCase: SessionRipgrepRunAction {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let sessionID: String
        let args: [String]
        let cwd: String?
    }

    private let service: any SessionRipgrepRunning
    private var inFlightTasks: [RequestKey: Task<APISessionBashResult, Error>] = [:]

    public init(service: any SessionRipgrepRunning) {
        self.service = service
    }

    public func runRipgrep(_ request: SessionArgumentCommandRequest) async throws -> APISessionBashResult {
        let (serverURL, normalizedToken, normalizedSessionID) = try normalizeSessionInputs(
            serverURLString: request.serverURLString,
            token: request.token,
            sessionID: request.sessionID
        )
        let normalizedArgs = request.arguments.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard !normalizedArgs.isEmpty else {
            throw SessionCommandError.missingArguments
        }
        let normalizedCWD = request.cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = RequestKey(
            serverURLString: serverURL.absoluteString,
            token: normalizedToken,
            sessionID: normalizedSessionID,
            args: normalizedArgs,
            cwd: normalizedCWD
        )
        if let inFlightTask = inFlightTasks[key] {
            return try await inFlightTask.value
        }

        let service = self.service
        let task = Task<APISessionBashResult, Error> {
            let result = try await service.runRipgrep(
                serverURL: serverURL,
                token: normalizedToken,
                sessionID: normalizedSessionID,
                args: normalizedArgs,
                cwd: normalizedCWD
            )
            if result.success {
                return result
            }
            let normalizedError = result.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SessionCommandError.failed(
                message: (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "Failed to run ripgrep"
            )
        }

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        return try await task.value
    }
}

public actor SessionDifftasticUseCase: SessionDifftasticRunAction {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let sessionID: String
        let args: [String]
        let cwd: String?
    }

    private let service: any SessionDifftasticRunning
    private var inFlightTasks: [RequestKey: Task<APISessionBashResult, Error>] = [:]

    public init(service: any SessionDifftasticRunning) {
        self.service = service
    }

    public func runDifftastic(_ request: SessionArgumentCommandRequest) async throws -> APISessionBashResult {
        let (serverURL, normalizedToken, normalizedSessionID) = try normalizeSessionInputs(
            serverURLString: request.serverURLString,
            token: request.token,
            sessionID: request.sessionID
        )
        let normalizedArgs = request.arguments.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard !normalizedArgs.isEmpty else {
            throw SessionCommandError.missingArguments
        }
        let normalizedCWD = request.cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = RequestKey(
            serverURLString: serverURL.absoluteString,
            token: normalizedToken,
            sessionID: normalizedSessionID,
            args: normalizedArgs,
            cwd: normalizedCWD
        )
        if let inFlightTask = inFlightTasks[key] {
            return try await inFlightTask.value
        }

        let service = self.service
        let task = Task<APISessionBashResult, Error> {
            let result = try await service.runDifftastic(
                serverURL: serverURL,
                token: normalizedToken,
                sessionID: normalizedSessionID,
                args: normalizedArgs,
                cwd: normalizedCWD
            )
            if result.success {
                return result
            }
            let normalizedError = result.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SessionCommandError.failed(
                message: (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "Failed to run difftastic"
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
