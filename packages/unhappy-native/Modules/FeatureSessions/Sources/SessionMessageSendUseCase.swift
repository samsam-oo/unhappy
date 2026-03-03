import Foundation
import CoreKit

public protocol SessionMessageSendingAction: Sendable {
    func sendMessage(
        serverURLString: String,
        token: String,
        sessionID: String,
        text: String,
        steerMode: APISessionSteerMode,
        permissionMode: APISessionMessagePermissionMode?,
        modelOverride: SessionMessageModelOverride,
        effortOverride: SessionMessageEffortOverride
    ) async throws -> APISessionSendMessageResult
}

public enum SessionMessageSendError: LocalizedError, Equatable {
    case missingToken
    case invalidServerURL
    case missingSessionID
    case missingMessageText
    case failed(message: String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .invalidServerURL:
            return "Invalid server URL"
        case .missingSessionID:
            return "Session ID is required"
        case .missingMessageText:
            return "Message text is required"
        case .failed(let message):
            return message
        }
    }
}

public actor SessionMessageSendUseCase: SessionMessageSendingAction {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let sessionID: String
        let text: String
        let steerMode: APISessionSteerMode
        let permissionMode: APISessionMessagePermissionMode?
        let modelOverride: SessionMessageModelOverride
        let effortOverride: SessionMessageEffortOverride
    }

    private let service: any SessionMessaging
    private var inFlightTasks: [RequestKey: Task<APISessionSendMessageResult, Error>] = [:]

    public init(service: any SessionMessaging) {
        self.service = service
    }

    public func sendMessage(
        serverURLString: String,
        token: String,
        sessionID: String,
        text: String,
        steerMode: APISessionSteerMode,
        permissionMode: APISessionMessagePermissionMode? = nil,
        modelOverride: SessionMessageModelOverride = .inherit,
        effortOverride: SessionMessageEffortOverride = .inherit
    ) async throws -> APISessionSendMessageResult {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw SessionMessageSendError.missingToken
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw SessionMessageSendError.invalidServerURL
        }

        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionMessageSendError.missingSessionID
        }

        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw SessionMessageSendError.missingMessageText
        }

        let key = RequestKey(
            serverURLString: normalizedURL,
            token: normalizedToken,
            sessionID: normalizedSessionID,
            text: normalizedText,
            steerMode: steerMode,
            permissionMode: permissionMode,
            modelOverride: modelOverride,
            effortOverride: effortOverride
        )
        if let inFlightTask = inFlightTasks[key] {
            return try await inFlightTask.value
        }

        let service = self.service
        let task = Task<APISessionSendMessageResult, Error> {
            let modelValue: String?
            let resetModel: Bool
            switch modelOverride {
            case .inherit:
                modelValue = nil
                resetModel = false
            case .reset:
                modelValue = nil
                resetModel = true
            case .set(let raw):
                let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if normalized.isEmpty {
                    modelValue = nil
                    resetModel = true
                } else {
                    modelValue = normalized
                    resetModel = false
                }
            }

            let effortValue = effortOverride.apiEffort
            let resetEffort = effortOverride == .auto

            let result = try await service.sendMessage(
                serverURL: serverURL,
                token: normalizedToken,
                sessionID: normalizedSessionID,
                text: normalizedText,
                steerMode: steerMode,
                permissionMode: permissionMode,
                model: modelValue,
                resetModel: resetModel,
                reasoningEffort: effortValue,
                resetReasoningEffort: resetEffort
            )
            if result.success {
                return result
            }
            let normalizedError = result.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SessionMessageSendError.failed(
                message: (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "Failed to send message"
            )
        }

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        return try await task.value
    }
}
