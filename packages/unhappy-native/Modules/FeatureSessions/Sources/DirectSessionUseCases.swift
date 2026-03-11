import Foundation
import CoreKit
import SessionKit

public struct DirectSessionIdentity: Identifiable, Equatable, Hashable, Sendable {
    public let machineID: String
    public let machineDisplayName: String
    public let wrappedMachineDataEncryptionKey: String?
    public let provider: APIUpstreamSessionProvider
    public let upstreamSessionID: String
    public let title: String
    public let cwd: String
    public let transcriptPath: String?
    public let model: String?
    public let effort: NewSessionReasoningEffort?
    public let permissionMode: APISessionMessagePermissionMode?
    public let collabInProgressCount: Int

    public init(
        machineID: String,
        machineDisplayName: String,
        wrappedMachineDataEncryptionKey: String? = nil,
        provider: APIUpstreamSessionProvider,
        upstreamSessionID: String,
        title: String,
        cwd: String,
        transcriptPath: String?,
        model: String?,
        effort: NewSessionReasoningEffort?,
        permissionMode: APISessionMessagePermissionMode?,
        collabInProgressCount: Int
    ) {
        self.machineID = machineID
        self.machineDisplayName = machineDisplayName
        self.wrappedMachineDataEncryptionKey = wrappedMachineDataEncryptionKey
        self.provider = provider
        self.upstreamSessionID = upstreamSessionID
        self.title = title
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.model = model
        self.effort = effort
        self.permissionMode = permissionMode
        self.collabInProgressCount = max(0, collabInProgressCount)
    }

    public var id: String {
        "\(machineID)|\(provider.rawValue)|\(upstreamSessionID)"
    }

    public var agent: APISessionSpawnAgent? {
        switch provider {
        case .codex:
            return .codex
        case .claude:
            return .claude
        case .gemini:
            return .gemini
        }
    }
}

public protocol DirectSessionMessagesLoadingAction: Sendable {
    func loadMessages(
        serverURLString: String,
        token: String,
        identity: DirectSessionIdentity,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage
}

public protocol DirectSessionMessageSendingAction: Sendable {
    func sendMessage(
        serverURLString: String,
        token: String,
        identity: DirectSessionIdentity,
        text: String,
        model: String?,
        reasoningEffort: APISessionReasoningEffort?,
        permissionMode: APISessionMessagePermissionMode?
    ) async throws -> APISessionSendMessageResult
}

public protocol DirectSessionArchivingAction: Sendable {
    func archiveSession(
        serverURLString: String,
        token: String,
        identity: DirectSessionIdentity
    ) async throws
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

public struct DirectSessionWorktreeSnapshot: Equatable, Sendable {
    public let repositoryRoot: String
    public let currentBranch: String
    public let worktreeListOutput: String
    public let statusOutput: String

    public init(
        repositoryRoot: String,
        currentBranch: String,
        worktreeListOutput: String,
        statusOutput: String
    ) {
        self.repositoryRoot = repositoryRoot
        self.currentBranch = currentBranch
        self.worktreeListOutput = worktreeListOutput
        self.statusOutput = statusOutput
    }
}

public protocol DirectSessionWorktreeLoadingAction: Sendable {
    func loadWorktreeSnapshot(
        serverURLString: String,
        token: String,
        identity: DirectSessionIdentity
    ) async throws -> DirectSessionWorktreeSnapshot
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
        identity: DirectSessionIdentity,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
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
                transcriptPath: normalizedTranscriptPath,
                wrappedMachineDataEncryptionKey: identity.wrappedMachineDataEncryptionKey,
                limit: limit,
                cursor: cursor
            )

        case .claude:
            return try await claudeService.fetchClaudeSessionMessages(
                serverURL: serverURL,
                token: normalizedToken,
                machineID: normalizedMachineID,
                sessionID: normalizedUpstreamSessionID,
                cwd: normalizedCWD,
                wrappedMachineDataEncryptionKey: identity.wrappedMachineDataEncryptionKey,
                limit: limit,
                cursor: cursor
            )

        case .gemini:
            return try await geminiService.fetchGeminiSessionMessages(
                serverURL: serverURL,
                token: normalizedToken,
                machineID: normalizedMachineID,
                sessionID: normalizedUpstreamSessionID,
                wrappedMachineDataEncryptionKey: identity.wrappedMachineDataEncryptionKey,
                limit: limit,
                cursor: cursor
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
        reasoningEffort: APISessionReasoningEffort? = nil,
        permissionMode: APISessionMessagePermissionMode? = nil
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
                wrappedMachineDataEncryptionKey: identity.wrappedMachineDataEncryptionKey,
                model: model,
                reasoningEffort: reasoningEffort,
                permissionMode: permissionMode,
                text: normalizedText
            )

        case .claude:
            result = try await claudeService.sendClaudeSessionMessage(
                serverURL: serverURL,
                token: normalizedToken,
                machineID: normalizedMachineID,
                sessionID: normalizedUpstreamSessionID,
                cwd: normalizedCWD,
                wrappedMachineDataEncryptionKey: identity.wrappedMachineDataEncryptionKey,
                model: model,
                reasoningEffort: reasoningEffort,
                permissionMode: permissionMode,
                text: normalizedText
            )

        case .gemini:
            result = try await geminiService.sendGeminiSessionMessage(
                serverURL: serverURL,
                token: normalizedToken,
                machineID: normalizedMachineID,
                sessionID: normalizedUpstreamSessionID,
                wrappedMachineDataEncryptionKey: identity.wrappedMachineDataEncryptionKey,
                model: model,
                permissionMode: permissionMode,
                text: normalizedText
            )
        }

        if result.success {
            return result
        }
        throw MachinesAPIError.rpcCallFailed(result.error ?? "Failed to send message")
    }
}

public actor DirectSessionArchiveUseCase: DirectSessionArchivingAction {
    private let codexService: any MachineCodexThreadArchiving

    public init(codexService: any MachineCodexThreadArchiving) {
        self.codexService = codexService
    }

    public func archiveSession(
        serverURLString: String,
        token: String,
        identity: DirectSessionIdentity
    ) async throws {
        guard identity.provider == .codex else {
            throw DirectSessionUseCaseError.failed(message: "Archiving is only available for Codex sessions")
        }

        let serverURL = try validatedServerURL(from: serverURLString)
        let normalizedToken = try validatedToken(token)
        let normalizedMachineID = try validatedMachineID(identity.machineID)
        let normalizedUpstreamSessionID = try validatedUpstreamSessionID(identity.upstreamSessionID)

        let result = try await codexService.archiveCodexThread(
            serverURL: serverURL,
            token: normalizedToken,
            machineID: normalizedMachineID,
            threadID: normalizedUpstreamSessionID,
            transcriptPath: identity.transcriptPath,
            wrappedMachineDataEncryptionKey: identity.wrappedMachineDataEncryptionKey
        )
        guard result.success else {
            throw DirectSessionUseCaseError.failed(
                message: result.error ?? result.message
            )
        }
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
                path: normalizedPath,
                wrappedMachineDataEncryptionKey: identity.wrappedMachineDataEncryptionKey
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
            wrappedMachineDataEncryptionKey: identity.wrappedMachineDataEncryptionKey,
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

public actor DirectSessionWorktreeLoadUseCase: DirectSessionWorktreeLoadingAction {
    private static let defaultTimeoutMilliseconds = 20_000
    private static let notGitRepositorySentinel = "__UNHAPPY_NOT_GIT_REPO__"
    private static let rootMarker = "__UNHAPPY_REPO_ROOT__"
    private static let branchMarker = "__UNHAPPY_BRANCH__"
    private static let worktreesMarker = "__UNHAPPY_WORKTREES__"
    private static let statusMarker = "__UNHAPPY_STATUS__"

    private let service: any MachineBashRunning

    public init(service: any MachineBashRunning) {
        self.service = service
    }

    public func loadWorktreeSnapshot(
        serverURLString: String,
        token: String,
        identity: DirectSessionIdentity
    ) async throws -> DirectSessionWorktreeSnapshot {
        let serverURL = try validatedServerURL(from: serverURLString)
        let normalizedToken = try validatedToken(token)
        let normalizedMachineID = try validatedMachineID(identity.machineID)
        let normalizedCWD = try validatedCWD(identity.cwd)

        let result = try await service.runBash(
            serverURL: serverURL,
            token: normalizedToken,
            machineID: normalizedMachineID,
            command: worktreeCommand,
            cwd: normalizedCWD,
            wrappedMachineDataEncryptionKey: identity.wrappedMachineDataEncryptionKey,
            timeoutMilliseconds: Self.defaultTimeoutMilliseconds
        )

        guard result.success else {
            let normalizedError = result.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw DirectSessionUseCaseError.failed(
                message: (normalizedError?.isEmpty == false ? normalizedError : nil) ??
                    (stderr.isEmpty ? "Failed to inspect worktree" : stderr)
            )
        }

        let normalizedStdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedStdout == Self.notGitRepositorySentinel {
            throw DirectSessionUseCaseError.failed(message: "Not a git repository")
        }

        return DirectSessionWorktreeSnapshot(
            repositoryRoot: extractDirectSessionWorktreeLine(
                prefixedBy: Self.rootMarker,
                from: normalizedStdout
            ) ?? normalizedCWD,
            currentBranch: extractDirectSessionWorktreeLine(
                prefixedBy: Self.branchMarker,
                from: normalizedStdout
            ) ?? "unknown",
            worktreeListOutput: extractDirectSessionWorktreeSection(
                between: Self.worktreesMarker,
                and: Self.statusMarker,
                from: normalizedStdout
            ) ?? "No worktree details",
            statusOutput: extractDirectSessionTrailingSection(
                after: Self.statusMarker,
                from: normalizedStdout
            ) ?? "No changes"
        )
    }

    private var worktreeCommand: String {
        """
        if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
          printf '\(Self.rootMarker)%s\\n' "$(git rev-parse --show-toplevel)"
          printf '\(Self.branchMarker)%s\\n' "$(git branch --show-current)"
          printf '\(Self.worktreesMarker)\\n'
          git worktree list --porcelain
          printf '\\n\(Self.statusMarker)\\n'
          git status --short --branch
        else
          printf '\(Self.notGitRepositorySentinel)'
        fi
        """
    }
}

private func extractDirectSessionWorktreeLine(prefixedBy marker: String, from output: String) -> String? {
    output
        .components(separatedBy: .newlines)
        .first(where: { $0.hasPrefix(marker) })?
        .replacingOccurrences(of: marker, with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func extractDirectSessionWorktreeSection(
    between startMarker: String,
    and endMarker: String,
    from output: String
) -> String? {
    guard let startRange = output.range(of: "\(startMarker)\n") else {
        return nil
    }
    let remaining = String(output[startRange.upperBound...])
    guard let endRange = remaining.range(of: "\n\(endMarker)") else {
        return nil
    }
    let section = String(remaining[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    return section.isEmpty ? nil : section
}

private func extractDirectSessionTrailingSection(after marker: String, from output: String) -> String? {
    guard let range = output.range(of: "\(marker)\n") else {
        return nil
    }
    let section = String(output[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    return section.isEmpty ? nil : section
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

private func validatedUpstreamSessionID(_ rawValue: String) throws -> String {
    let normalizedSessionID = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedSessionID.isEmpty else {
        throw DirectSessionUseCaseError.missingUpstreamSessionID
    }
    return normalizedSessionID
}

private func validatedCWD(_ rawValue: String) throws -> String {
    let normalizedCWD = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedCWD.isEmpty else {
        throw DirectSessionUseCaseError.missingCWD
    }
    return normalizedCWD
}
