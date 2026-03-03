import Foundation
import Testing
@testable import FeatureSessions
import CoreKit

struct SessionMessageSendUseCaseTests {
    @Test
    func sendMessageThrowsMissingText() async {
        let useCase = SessionMessageSendUseCase(
            service: MessageService(result: .init(success: true, queueCount: nil, queuedMessages: nil, error: nil))
        )

        await #expect(throws: SessionMessageSendError.missingMessageText) {
            _ = try await useCase.sendMessage(
                serverURLString: "https://api.unhappy.im",
                token: "token",
                sessionID: "session-1",
                text: " ",
                steerMode: APISessionSteerMode.queue
            )
        }
    }

    @Test
    func sendMessageReturnsSuccessResult() async throws {
        let useCase = SessionMessageSendUseCase(
            service: MessageService(result: .init(success: true, queueCount: nil, queuedMessages: nil, error: nil))
        )

        let result = try await useCase.sendMessage(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            sessionID: "session-1",
            text: "run tests",
            steerMode: APISessionSteerMode.immediate
        )

        #expect(result.success == true)
    }
}

private struct MessageService: SessionMessaging {
    let result: APISessionSendMessageResult

    func sendMessage(
        serverURL: URL,
        token: String,
        sessionID: String,
        text: String,
        steerMode: APISessionSteerMode?,
        permissionMode: APISessionMessagePermissionMode?,
        model: String?,
        resetModel: Bool,
        reasoningEffort: APISessionReasoningEffort?,
        resetReasoningEffort: Bool
    ) async throws -> APISessionSendMessageResult {
        result
    }
}
