import Foundation
import CoreKit

public struct DirectSessionIdentity: Identifiable, Equatable, Hashable, Sendable {
    public let machineID: String
    public let machineDisplayName: String
    public let provider: APIUpstreamSessionProvider
    public let upstreamSessionID: String
    public let title: String
    public let cwd: String
    public let transcriptPath: String?
    public let model: String?

    public init(
        machineID: String,
        machineDisplayName: String,
        provider: APIUpstreamSessionProvider,
        upstreamSessionID: String,
        title: String,
        cwd: String,
        transcriptPath: String?,
        model: String?
    ) {
        self.machineID = machineID
        self.machineDisplayName = machineDisplayName
        self.provider = provider
        self.upstreamSessionID = upstreamSessionID
        self.title = title
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.model = model
    }

    public var id: String {
        "\(machineID)|\(provider.rawValue)|\(upstreamSessionID)"
    }
}

public protocol DirectSessionMessagesLoadingAction: Sendable {
    func loadMessages(
        serverURLString: String,
        token: String,
        identity: DirectSessionIdentity
    ) async throws -> [APISessionMessage]
}

public protocol DirectSessionMessageSendingAction: Sendable {
    func sendMessage(
        serverURLString: String,
        token: String,
        identity: DirectSessionIdentity,
        text: String
    ) async throws -> APISessionSendMessageResult
}

public enum DirectSessionUseCaseError: LocalizedError, Equatable {
    case missingToken
    case invalidServerURL
    case missingMachineID
    case missingUpstreamSessionID
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
        case .missingUpstreamSessionID:
            return "Session ID is required"
        case .missingTranscriptPath:
            return "Transcript path is required"
        case .missingCWD:
            return "Working directory is required"
        case .missingMessageText:
            return "Message text is required"
        }
    }
}

public actor DirectSessionMessagesLoadUseCase: DirectSessionMessagesLoadingAction {
    private let codexService: any MachineCodexThreadMessagesFetching
    private let claudeService: any MachineClaudeSessionMessagesFetching
    private let geminiService: any MachineGeminiSessionMessagesFetching

    public init(
        codexService: any MachineCodexThreadMessagesFetching,
        claudeService: any MachineClaudeSessionMessagesFetching,
        geminiService: any MachineGeminiSessionMessagesFetching
    ) {
        self.codexService = codexService
        self.claudeService = claudeService
        self.geminiService = geminiService
    }

    public func loadMessages(
        serverURLString: String,
        token: String,
        identity: DirectSessionIdentity
    ) async throws -> [APISessionMessage] {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw DirectSessionUseCaseError.missingToken
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw DirectSessionUseCaseError.invalidServerURL
        }

        let normalizedMachineID = identity.machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw DirectSessionUseCaseError.missingMachineID
        }

        let normalizedUpstreamSessionID = identity.upstreamSessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUpstreamSessionID.isEmpty else {
            throw DirectSessionUseCaseError.missingUpstreamSessionID
        }

        let normalizedCWD = identity.cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCWD.isEmpty else {
            throw DirectSessionUseCaseError.missingCWD
        }

        switch identity.provider {
        case .codex:
            let normalizedTranscriptPath = identity.transcriptPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !normalizedTranscriptPath.isEmpty else {
                throw DirectSessionUseCaseError.missingTranscriptPath
            }
            return try await codexService.fetchCodexThreadMessages(
                serverURL: serverURL,
                token: normalizedToken,
                machineID: normalizedMachineID,
                threadID: normalizedUpstreamSessionID,
                transcriptPath: normalizedTranscriptPath
            )

        case .claude:
            return try await claudeService.fetchClaudeSessionMessages(
                serverURL: serverURL,
                token: normalizedToken,
                machineID: normalizedMachineID,
                sessionID: normalizedUpstreamSessionID,
                cwd: normalizedCWD
            )

        case .gemini:
            return try await geminiService.fetchGeminiSessionMessages(
                serverURL: serverURL,
                token: normalizedToken,
                machineID: normalizedMachineID,
                sessionID: normalizedUpstreamSessionID
            )
        }
    }
}

public actor DirectSessionMessageSendUseCase: DirectSessionMessageSendingAction {
    private let codexService: any MachineCodexThreadMessaging
    private let claudeService: any MachineClaudeSessionMessaging
    private let geminiService: any MachineGeminiSessionMessaging

    public init(
        codexService: any MachineCodexThreadMessaging,
        claudeService: any MachineClaudeSessionMessaging,
        geminiService: any MachineGeminiSessionMessaging
    ) {
        self.codexService = codexService
        self.claudeService = claudeService
        self.geminiService = geminiService
    }

    public func sendMessage(
        serverURLString: String,
        token: String,
        identity: DirectSessionIdentity,
        text: String
    ) async throws -> APISessionSendMessageResult {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw DirectSessionUseCaseError.missingToken
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw DirectSessionUseCaseError.invalidServerURL
        }

        let normalizedMachineID = identity.machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw DirectSessionUseCaseError.missingMachineID
        }

        let normalizedUpstreamSessionID = identity.upstreamSessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUpstreamSessionID.isEmpty else {
            throw DirectSessionUseCaseError.missingUpstreamSessionID
        }

        let normalizedCWD = identity.cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCWD.isEmpty else {
            throw DirectSessionUseCaseError.missingCWD
        }

        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw DirectSessionUseCaseError.missingMessageText
        }

        let result: APISessionSendMessageResult
        switch identity.provider {
        case .codex:
            let normalizedTranscriptPath = identity.transcriptPath?.trimmingCharacters(in: .whitespacesAndNewlines)
            result = try await codexService.sendCodexThreadMessage(
                serverURL: serverURL,
                token: normalizedToken,
                machineID: normalizedMachineID,
                threadID: normalizedUpstreamSessionID,
                cwd: normalizedCWD,
                transcriptPath: normalizedTranscriptPath?.isEmpty == true ? nil : normalizedTranscriptPath,
                text: normalizedText
            )

        case .claude:
            result = try await claudeService.sendClaudeSessionMessage(
                serverURL: serverURL,
                token: normalizedToken,
                machineID: normalizedMachineID,
                sessionID: normalizedUpstreamSessionID,
                cwd: normalizedCWD,
                text: normalizedText
            )

        case .gemini:
            result = try await geminiService.sendGeminiSessionMessage(
                serverURL: serverURL,
                token: normalizedToken,
                machineID: normalizedMachineID,
                sessionID: normalizedUpstreamSessionID,
                text: normalizedText
            )
        }

        if result.success {
            return result
        }
        throw MachinesAPIError.rpcCallFailed(result.error ?? "Failed to send message")
    }
}
