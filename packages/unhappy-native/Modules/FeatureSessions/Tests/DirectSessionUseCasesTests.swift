import Foundation
import Testing
import CoreKit
import SessionKit
@testable import FeatureSessions

struct DirectSessionUseCasesTests {
    @Test
    func loadMessagesUsesGeminiDirectService() async throws {
        let service = GeminiMessagesService(
            messages: [
                APISessionMessage(
                    id: "gemini-msg-1",
                    seq: 1,
                    localId: nil,
                    content: APIEncryptedMessageContent(type: "text", payload: "{}"),
                    createdAt: 1,
                    updatedAt: 1
                )
            ]
        )
        let useCase = DirectSessionMessagesLoadUseCase(
            codexService: FailingCodexMessagesService(),
            claudeService: FailingClaudeMessagesService(),
            geminiService: service
        )

        let page = try await useCase.loadMessages(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            identity: DirectSessionIdentity(
                machineID: "machine-1",
                machineDisplayName: "Mac",
                wrappedMachineDataEncryptionKey: nil,
                provider: .gemini,
                upstreamSessionID: "gemini-session-1",
                title: "Gemini Session",
                cwd: "/repo",
                transcriptPath: nil,
                model: "gemini-3-flash-preview",
                effort: nil,
                permissionMode: nil,
                collabInProgressCount: 0
            ),
            limit: 120,
            cursor: nil
        )

        #expect(page.messages.count == 1)
        let recordedSessionID = await service.recordedSessionID
        #expect(recordedSessionID == "gemini-session-1")
    }

    @Test
    func sendMessageUsesGeminiDirectService() async throws {
        let service = GeminiMessagingService()
        let useCase = DirectSessionMessageSendUseCase(
            codexService: FailingCodexMessagingService(),
            claudeService: FailingClaudeMessagingService(),
            geminiService: service
        )

        let result = try await useCase.sendMessage(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            identity: DirectSessionIdentity(
                machineID: "machine-1",
                machineDisplayName: "Mac",
                wrappedMachineDataEncryptionKey: nil,
                provider: .gemini,
                upstreamSessionID: "gemini-session-1",
                title: "Gemini Session",
                cwd: "/repo",
                transcriptPath: nil,
                model: "gemini-3-flash-preview",
                effort: nil,
                permissionMode: nil,
                collabInProgressCount: 0
            ),
            text: "hello gemini",
            model: nil,
            reasoningEffort: nil,
            permissionMode: nil
        )

        #expect(result.success == true)
        let recorded = await service.recordedCall
        #expect(recorded?.sessionID == "gemini-session-1")
        #expect(recorded?.text == "hello gemini")
    }

    @Test
    func loadFileDecodesBase64ContentFromMachineService() async throws {
        let service = FileReadingService()
        let useCase = DirectSessionFileLoadUseCase(service: service)

        let content = try await useCase.loadFile(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            identity: DirectSessionIdentity(
                machineID: "machine-1",
                machineDisplayName: "Mac",
                wrappedMachineDataEncryptionKey: nil,
                provider: .codex,
                upstreamSessionID: "thread-1",
                title: "Codex Session",
                cwd: "/repo",
                transcriptPath: "/repo/.codex/transcript.jsonl",
                model: "gpt-5-codex",
                effort: nil,
                permissionMode: nil,
                collabInProgressCount: 0
            ),
            path: "Sources/App.swift"
        )

        #expect(content == "print(\"hello\")")
        let recordedPath = await service.recordedPath
        #expect(recordedPath == "Sources/App.swift")
    }

    @Test
    func loadReviewUsesMachineBashService() async throws {
        let service = BashRunningService(
            result: APISessionBashResult(
                success: true,
                stdout: "diff --git a/App.swift b/App.swift\n@@ -1 +1 @@\n-old\n+new\n",
                stderr: "",
                exitCode: 0,
                error: nil
            )
        )
        let useCase = DirectSessionReviewLoadUseCase(service: service)

        let output = try await useCase.loadReview(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            identity: DirectSessionIdentity(
                machineID: "machine-1",
                machineDisplayName: "Mac",
                wrappedMachineDataEncryptionKey: nil,
                provider: .claude,
                upstreamSessionID: "claude-session-1",
                title: "Claude Session",
                cwd: "/repo",
                transcriptPath: nil,
                model: "sonnet",
                effort: nil,
                permissionMode: nil,
                collabInProgressCount: 0
            ),
            repositoryPath: nil
        )

        #expect(output.diffText.contains("diff --git a/App.swift b/App.swift"))
        #expect(output.statusMessage == "Loaded review diff")
        let recorded = await service.recordedCall
        #expect(recorded?.cwd == "/repo")
        #expect(recorded?.command.contains("git diff --no-ext-diff") == true)
    }
}

private actor FileReadingService: MachineFileReading {
    private(set) var recordedPath: String?

    func readFile(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APISessionReadFileResult {
        recordedPath = path
        return APISessionReadFileResult(
            success: true,
            content: Data("print(\"hello\")".utf8).base64EncodedString(),
            error: nil
        )
    }
}

private actor BashRunningService: MachineBashRunning {
    struct RecordedCall: Equatable {
        let command: String
        let cwd: String
        let timeoutMilliseconds: Int
    }

    let result: APISessionBashResult
    private(set) var recordedCall: RecordedCall?

    init(result: APISessionBashResult) {
        self.result = result
    }

    func runBash(
        serverURL: URL,
        token: String,
        machineID: String,
        command: String,
        cwd: String,
        wrappedMachineDataEncryptionKey: String?,
        timeoutMilliseconds: Int
    ) async throws -> APISessionBashResult {
        recordedCall = RecordedCall(
            command: command,
            cwd: cwd,
            timeoutMilliseconds: timeoutMilliseconds
        )
        return result
    }
}

private actor GeminiMessagesService: MachineGeminiSessionMessagesFetching {
    let messages: [APISessionMessage]
    private(set) var recordedSessionID: String?

    init(messages: [APISessionMessage]) {
        self.messages = messages
    }

    func fetchGeminiSessionMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        recordedSessionID = sessionID
        return APISessionMessagesPage(messages: messages, nextCursor: cursor, hasNext: false)
    }
}

private actor GeminiMessagingService: MachineGeminiSessionMessaging {
    struct RecordedCall: Equatable {
        let sessionID: String
        let text: String
    }

    private(set) var recordedCall: RecordedCall?

    func sendGeminiSessionMessage(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        wrappedMachineDataEncryptionKey: String?,
        model: String?,
        permissionMode: APISessionMessagePermissionMode?,
        text: String
    ) async throws -> APISessionSendMessageResult {
        recordedCall = RecordedCall(sessionID: sessionID, text: text)
        return APISessionSendMessageResult(
            success: true,
            queueCount: nil,
            queuedMessages: nil,
            error: nil
        )
    }
}

private actor FailingCodexMessagesService: MachineCodexThreadMessagesFetching {
    func fetchCodexThreadMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        threadID: String,
        transcriptPath: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        Issue.record("Codex service should not be used")
        return APISessionMessagesPage(messages: [], nextCursor: cursor, hasNext: false)
    }
}

private actor FailingClaudeMessagesService: MachineClaudeSessionMessagesFetching {
    func fetchClaudeSessionMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        cwd: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        Issue.record("Claude service should not be used")
        return APISessionMessagesPage(messages: [], nextCursor: cursor, hasNext: false)
    }
}

private actor FailingCodexMessagingService: MachineCodexThreadMessaging {
    func sendCodexThreadMessage(
        serverURL: URL,
        token: String,
        machineID: String,
        threadID: String,
        cwd: String,
        transcriptPath: String?,
        wrappedMachineDataEncryptionKey: String?,
        model: String?,
        reasoningEffort: APISessionReasoningEffort?,
        permissionMode: APISessionMessagePermissionMode?,
        text: String
    ) async throws -> APISessionSendMessageResult {
        Issue.record("Codex service should not be used")
        return APISessionSendMessageResult(
            success: false,
            queueCount: nil,
            queuedMessages: nil,
            error: "unexpected"
        )
    }
}

private actor FailingClaudeMessagingService: MachineClaudeSessionMessaging {
    func sendClaudeSessionMessage(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        cwd: String,
        wrappedMachineDataEncryptionKey: String?,
        model: String?,
        reasoningEffort: APISessionReasoningEffort?,
        permissionMode: APISessionMessagePermissionMode?,
        text: String
    ) async throws -> APISessionSendMessageResult {
        Issue.record("Claude service should not be used")
        return APISessionSendMessageResult(
            success: false,
            queueCount: nil,
            queuedMessages: nil,
            error: "unexpected"
        )
    }
}
