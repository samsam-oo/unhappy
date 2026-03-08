import Foundation
import Testing
import CoreKit
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

        let messages = try await useCase.loadMessages(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            identity: DirectSessionIdentity(
                machineID: "machine-1",
                machineDisplayName: "Mac",
                provider: .gemini,
                upstreamSessionID: "gemini-session-1",
                title: "Gemini Session",
                cwd: "/repo",
                transcriptPath: nil,
                model: "gemini-3-flash-preview"
            )
        )

        #expect(messages.count == 1)
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
                provider: .gemini,
                upstreamSessionID: "gemini-session-1",
                title: "Gemini Session",
                cwd: "/repo",
                transcriptPath: nil,
                model: "gemini-3-flash-preview"
            ),
            text: "hello gemini"
        )

        #expect(result.success == true)
        let recorded = await service.recordedCall
        #expect(recorded?.sessionID == "gemini-session-1")
        #expect(recorded?.text == "hello gemini")
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
        sessionID: String
    ) async throws -> [APISessionMessage] {
        recordedSessionID = sessionID
        return messages
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
        transcriptPath: String
    ) async throws -> [APISessionMessage] {
        Issue.record("Codex service should not be used")
        return []
    }
}

private actor FailingClaudeMessagesService: MachineClaudeSessionMessagesFetching {
    func fetchClaudeSessionMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        cwd: String
    ) async throws -> [APISessionMessage] {
        Issue.record("Claude service should not be used")
        return []
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
