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
        text: String,
        model: String?,
        reasoningEffort: APISessionReasoningEffort?
    ) async throws -> APISessionSendMessageResult
}

public protocol DirectSessionFileLoadingAction: Sendable {
    func loadFile(
        serverURLString: String,
        token: String,
        identity: DirectSessionIdentity,
        path: String
    ) async throws -> String
}

public struct DirectSessionReviewOutput: Equatable, Sendable {
    public let diffText: String
    public let statusMessage: String?

    public init(diffText: String, statusMessage: String?) {
        self.diffText = diffText
        self.statusMessage = statusMessage
    }
}

public protocol DirectSessionReviewLoadingAction: Sendable {
    func loadReview(
        serverURLString: String,
        token: String,
        identity: DirectSessionIdentity,
        repositoryPath: String?
    ) async throws -> DirectSessionReviewOutput
}

public enum DirectSessionUseCaseError: LocalizedError, Equatable {
    case missingToken
    case invalidServerURL
    case missingMachineID
    case missingUpstreamSessionID
    case missingTranscriptPath
    case missingCWD
    case missingPath
    case missingMessageText
    case invalidBase64Content
    case failed(message: String)

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
        case .missingPath:
            return "Path is required"
        case .missingMessageText:
            return "Message text is required"
        case .invalidBase64Content:
            return "File payload is not valid base64"
        case .failed(let message):
            return message
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
        text: String,
        model: String? = nil,
        reasoningEffort: APISessionReasoningEffort? = nil
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
                model: model,
                reasoningEffort: reasoningEffort,
                text: normalizedText
            )

        case .claude:
            result = try await claudeService.sendClaudeSessionMessage(
                serverURL: serverURL,
                token: normalizedToken,
                machineID: normalizedMachineID,
                sessionID: normalizedUpstreamSessionID,
                cwd: normalizedCWD,
                model: model,
                reasoningEffort: reasoningEffort,
                text: normalizedText
            )

        case .gemini:
            result = try await geminiService.sendGeminiSessionMessage(
                serverURL: serverURL,
                token: normalizedToken,
                machineID: normalizedMachineID,
                sessionID: normalizedUpstreamSessionID,
                model: model,
                text: normalizedText
            )
        }

        if result.success {
            return result
        }
        throw MachinesAPIError.rpcCallFailed(result.error ?? "Failed to send message")
    }
}

public actor DirectSessionFileLoadUseCase: DirectSessionFileLoadingAction {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let machineID: String
        let path: String
    }

    private static let maxRenderedBytes = 300_000

    private let service: any MachineFileReading
    private var inFlightTasks: [RequestKey: Task<String, Error>] = [:]

    public init(service: any MachineFileReading) {
        self.service = service
    }

    public func loadFile(
        serverURLString: String,
        token: String,
        identity: DirectSessionIdentity,
        path: String
    ) async throws -> String {
        let serverURL = try validatedServerURL(from: serverURLString)
        let normalizedToken = try validatedToken(token)
        let normalizedMachineID = try validatedMachineID(identity.machineID)
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw DirectSessionUseCaseError.missingPath
        }

        let key = RequestKey(
            serverURLString: serverURL.absoluteString,
            token: normalizedToken,
            machineID: normalizedMachineID,
            path: normalizedPath
        )
        if let inFlightTask = inFlightTasks[key] {
            return try await inFlightTask.value
        }

        let service = self.service
        let task = Task<String, Error> {
            let result = try await service.readFile(
                serverURL: serverURL,
                token: normalizedToken,
                machineID: normalizedMachineID,
                path: normalizedPath
            )

            guard result.success else {
                let normalizedError = result.error?.trimmingCharacters(in: .whitespacesAndNewlines)
                throw DirectSessionUseCaseError.failed(
                    message: (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "Failed to read file"
                )
            }

            guard let encoded = result.content else {
                throw DirectSessionUseCaseError.failed(message: "File response did not contain content")
            }
            guard let data = Data(base64Encoded: encoded) else {
                throw DirectSessionUseCaseError.invalidBase64Content
            }

            if data.count > Self.maxRenderedBytes {
                let prefix = data.prefix(Self.maxRenderedBytes)
                let truncatedText = String(decoding: prefix, as: UTF8.self)
                return "\(truncatedText)\n\n[truncated: showing first \(Self.maxRenderedBytes) bytes]"
            }

            return String(decoding: data, as: UTF8.self)
        }

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        return try await task.value
    }
}

public actor DirectSessionReviewLoadUseCase: DirectSessionReviewLoadingAction {
    private static let defaultTimeoutMilliseconds = 20_000
    private static let notGitRepositorySentinel = "__UNHAPPY_NOT_GIT_REPO__"
    private static let noChangesStatus = "No changes"

    private let service: any MachineBashRunning

    public init(service: any MachineBashRunning) {
        self.service = service
    }

    public func loadReview(
        serverURLString: String,
        token: String,
        identity: DirectSessionIdentity,
        repositoryPath: String?
    ) async throws -> DirectSessionReviewOutput {
        let serverURL = try validatedServerURL(from: serverURLString)
        let normalizedToken = try validatedToken(token)
        let normalizedMachineID = try validatedMachineID(identity.machineID)
        let normalizedRepositoryPath = repositoryPath?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackWorkingDirectory = try validatedCWD(identity.cwd)
        let workingDirectory = (normalizedRepositoryPath?.isEmpty == false ? normalizedRepositoryPath : nil) ??
            fallbackWorkingDirectory

        let result = try await service.runBash(
            serverURL: serverURL,
            token: normalizedToken,
            machineID: normalizedMachineID,
            command: reviewCommand,
            cwd: workingDirectory,
            timeoutMilliseconds: Self.defaultTimeoutMilliseconds
        )

        guard result.success else {
            let normalizedError = result.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw DirectSessionUseCaseError.failed(
                message: (normalizedError?.isEmpty == false ? normalizedError : nil) ??
                    (stderr.isEmpty ? "Failed to load review diff" : stderr)
            )
        }

        let normalizedStdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedStdout == Self.notGitRepositorySentinel {
            throw DirectSessionUseCaseError.failed(message: "Not a git repository")
        }

        guard !normalizedStdout.isEmpty else {
            return DirectSessionReviewOutput(diffText: "", statusMessage: Self.noChangesStatus)
        }

        return DirectSessionReviewOutput(
            diffText: normalizedStdout,
            statusMessage: "Loaded review diff"
        )
    }

    private var reviewCommand: String {
        """
        if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
          git diff --no-ext-diff --stat
          printf '\\n'
          git diff --no-ext-diff
        else
          printf '\(Self.notGitRepositorySentinel)'
        fi
        """
    }
}

private func validatedToken(_ token: String) throws -> String {
    let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedToken.isEmpty else {
        throw DirectSessionUseCaseError.missingToken
    }
    return normalizedToken
}

private func validatedServerURL(from rawValue: String) throws -> URL {
    let normalizedURL = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
        !normalizedURL.isEmpty,
        let serverURL = URL(string: normalizedURL),
        serverURL.scheme != nil,
        serverURL.host != nil
    else {
        throw DirectSessionUseCaseError.invalidServerURL
    }
    return serverURL
}

private func validatedMachineID(_ rawValue: String) throws -> String {
    let normalizedMachineID = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedMachineID.isEmpty else {
        throw DirectSessionUseCaseError.missingMachineID
    }
    return normalizedMachineID
}

private func validatedCWD(_ rawValue: String) throws -> String {
    let normalizedCWD = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedCWD.isEmpty else {
        throw DirectSessionUseCaseError.missingCWD
    }
    return normalizedCWD
}
