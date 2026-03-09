import Foundation
import Testing
import CoreKit
@testable import FeatureSessions

@MainActor
struct DirectSessionViewModelTests {
    @Test
    func sendMessageReturnsBeforeBackgroundRefreshCompletes() async throws {
        let loader = BlockingMessagesLoader()
        let sender = SuccessfulSender()
        let viewModel = DirectSessionViewModel(
            identity: makeIdentity(),
            loader: loader,
            sender: sender
        )

        let sendTask = Task {
            await viewModel.sendMessage(
                "hello",
                serverURLString: "https://api.unhappy.im",
                token: "token"
            )
        }

        let completedImmediately = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await sendTask.value }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(20))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        #expect(completedImmediately == true)

        try await Task.sleep(for: .milliseconds(350))
        let recordedCallCount = await loader.recordedCallCount
        #expect(recordedCallCount == 1)
    }

    @Test
    func sendMessageUsesSmallerBackgroundRefreshLimitAfterMessagesExist() async throws {
        let loader = RecordingMessagesLoader()
        let sender = SuccessfulSender()
        let viewModel = DirectSessionViewModel(
            identity: makeIdentity(),
            loader: loader,
            sender: sender
        )

        await viewModel.load(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )
        _ = await viewModel.sendMessage(
            "hello again",
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )
        try await Task.sleep(for: .milliseconds(350))

        let recordedLimits = await loader.recordedLimits
        #expect(recordedLimits == [120, 40])
    }

    private func makeIdentity() -> DirectSessionIdentity {
        DirectSessionIdentity(
            machineID: "machine-1",
            machineDisplayName: "Mac",
            wrappedMachineDataEncryptionKey: nil,
            provider: .gemini,
            upstreamSessionID: "session-1",
            title: "Session",
            cwd: "/repo",
            transcriptPath: nil,
            model: "gemini-3-flash-preview",
            effort: nil,
            permissionMode: nil,
            collabInProgressCount: 0
        )
    }
}

private actor BlockingMessagesLoader: DirectSessionMessagesLoadingAction {
    private(set) var recordedCallCount = 0

    func loadMessages(
        serverURLString: String,
        token: String,
        identity: DirectSessionIdentity,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        recordedCallCount += 1
        try await Task.sleep(for: .seconds(1))
        return APISessionMessagesPage(messages: [], nextCursor: nil, hasNext: false)
    }
}

private actor RecordingMessagesLoader: DirectSessionMessagesLoadingAction {
    private(set) var recordedLimits: [Int] = []

    func loadMessages(
        serverURLString: String,
        token: String,
        identity: DirectSessionIdentity,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        recordedLimits.append(limit)
        return APISessionMessagesPage(
            messages: [
                APISessionMessage(
                    id: UUID().uuidString,
                    seq: recordedLimits.count,
                    localId: nil,
                    content: APIEncryptedMessageContent(type: "text", payload: "{}"),
                    createdAt: TimeInterval(recordedLimits.count),
                    updatedAt: TimeInterval(recordedLimits.count)
                )
            ],
            nextCursor: nil,
            hasNext: false
        )
    }
}

private actor SuccessfulSender: DirectSessionMessageSendingAction {
    func sendMessage(
        serverURLString: String,
        token: String,
        identity: DirectSessionIdentity,
        text: String,
        model: String?,
        reasoningEffort: APISessionReasoningEffort?,
        permissionMode: APISessionMessagePermissionMode?
    ) async throws -> APISessionSendMessageResult {
        APISessionSendMessageResult(success: true, queueCount: 1, queuedMessages: [text], error: nil)
    }
}
