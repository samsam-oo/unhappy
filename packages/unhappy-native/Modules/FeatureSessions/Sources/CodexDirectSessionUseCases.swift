import Foundation
import CoreKit

public struct CodexDirectSessionIdentity: Equatable, Hashable, Sendable {
    public let machineID: String
    public let machineDisplayName: String
    public let threadID: String
    public let title: String
    public let cwd: String
    public let transcriptPath: String
    public let model: String?

    public init(
        machineID: String,
        machineDisplayName: String,
        threadID: String,
        title: String,
        cwd: String,
        transcriptPath: String,
        model: String?
    ) {
        self.machineID = machineID
        self.machineDisplayName = machineDisplayName
        self.threadID = threadID
        self.title = title
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.model = model
    }
}

public protocol CodexDirectSessionMessagesLoadingAction: Sendable {
    func loadMessages(
        serverURLString: String,
        token: String,
        identity: CodexDirectSessionIdentity
    ) async throws -> [APISessionMessage]
}

public protocol CodexDirectSessionMessageSendingAction: Sendable {
    func sendMessage(
        serverURLString: String,
        token: String,
        identity: CodexDirectSessionIdentity,
        text: String
    ) async throws -> APISessionSendMessageResult
}

public enum CodexDirectSessionUseCaseError: LocalizedError, Equatable {
    case missingToken
    case invalidServerURL
    case missingMachineID
    case missingThreadID
    case missingTranscriptPath
    case missingCWD
    case missingMessageText

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .invalidServerURL:
            return "Invalid server URL"
        case .missingMachineID:
            return "Machine ID is required"
        case .missingThreadID:
            return "Thread ID is required"
        case .missingTranscriptPath:
            return "Transcript path is required"
        case .missingCWD:
            return "Working directory is required"
        case .missingMessageText:
            return "Message text is required"
        }
    }
}

public actor CodexDirectSessionMessagesLoadUseCase: CodexDirectSessionMessagesLoadingAction {
    private let service: any MachineCodexThreadMessagesFetching

    public init(service: any MachineCodexThreadMessagesFetching) {
        self.service = service
    }

    public func loadMessages(
        serverURLString: String,
        token: String,
        identity: CodexDirectSessionIdentity
    ) async throws -> [APISessionMessage] {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw CodexDirectSessionUseCaseError.missingToken
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw CodexDirectSessionUseCaseError.invalidServerURL
        }

        let normalizedMachineID = identity.machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw CodexDirectSessionUseCaseError.missingMachineID
        }

        let normalizedThreadID = identity.threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedThreadID.isEmpty else {
            throw CodexDirectSessionUseCaseError.missingThreadID
        }

        let normalizedTranscriptPath = identity.transcriptPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTranscriptPath.isEmpty else {
            throw CodexDirectSessionUseCaseError.missingTranscriptPath
        }

        return try await service.fetchCodexThreadMessages(
            serverURL: serverURL,
            token: normalizedToken,
            machineID: normalizedMachineID,
            threadID: normalizedThreadID,
            transcriptPath: normalizedTranscriptPath
        )
    }
}

public actor CodexDirectSessionMessageSendUseCase: CodexDirectSessionMessageSendingAction {
    private let service: any MachineCodexThreadMessaging

    public init(service: any MachineCodexThreadMessaging) {
        self.service = service
    }

    public func sendMessage(
        serverURLString: String,
        token: String,
        identity: CodexDirectSessionIdentity,
        text: String
    ) async throws -> APISessionSendMessageResult {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw CodexDirectSessionUseCaseError.missingToken
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw CodexDirectSessionUseCaseError.invalidServerURL
        }

        let normalizedMachineID = identity.machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw CodexDirectSessionUseCaseError.missingMachineID
        }

        let normalizedThreadID = identity.threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedThreadID.isEmpty else {
            throw CodexDirectSessionUseCaseError.missingThreadID
        }

        let normalizedCWD = identity.cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCWD.isEmpty else {
            throw CodexDirectSessionUseCaseError.missingCWD
        }

        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw CodexDirectSessionUseCaseError.missingMessageText
        }

        let normalizedTranscriptPath = identity.transcriptPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try await service.sendCodexThreadMessage(
            serverURL: serverURL,
            token: normalizedToken,
            machineID: normalizedMachineID,
            threadID: normalizedThreadID,
            cwd: normalizedCWD,
            transcriptPath: normalizedTranscriptPath.isEmpty ? nil : normalizedTranscriptPath,
            text: normalizedText
        )
        if result.success {
            return result
        }
        throw MachinesAPIError.rpcCallFailed(result.error ?? "Failed to send message")
    }
}
