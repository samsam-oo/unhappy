import Foundation
import Testing
import CoreKit
import SessionKit
@testable import FeatureSessions

@MainActor
struct DirectSessionViewModelTests {
    @Test
    func pollingStrategyUsesSmallerRefreshLimitWhenMessagesExist() {
        let limit = DirectSessionPollingStrategy.refreshLimit(
            hasExistingMessages: true,
            defaultPageSize: 120
        )

        #expect(limit == 20)
    }

    @Test
    func loadUsesLiveReconnectStatusForTransientDataPlaneFailures() async {
        let viewModel = DirectSessionViewModel(
            identity: makeIdentity(),
            loader: ReconnectingMessagesLoader(),
            sender: SuccessfulSender()
        )

        await viewModel.load(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.liveStatusText == "Reconnecting to machine…")
    }

    @Test
    func pollingStrategySkipsRefreshWhileSendOrPostSendRefreshIsPending() {
        #expect(
            DirectSessionPollingStrategy.shouldRefreshLatestMessages(
                hasExistingMessages: true,
                isSending: true,
                isLoadingOlderMessages: false,
                hasPendingPostSendRefresh: false,
                hasActiveMessagesLoad: false
            ) == false
        )
        #expect(
            DirectSessionPollingStrategy.shouldRefreshLatestMessages(
                hasExistingMessages: true,
                isSending: false,
                isLoadingOlderMessages: false,
                hasPendingPostSendRefresh: true,
                hasActiveMessagesLoad: false
            ) == false
        )
        #expect(
            DirectSessionPollingStrategy.shouldRefreshLatestMessages(
                hasExistingMessages: true,
                isSending: false,
                isLoadingOlderMessages: false,
                hasPendingPostSendRefresh: false,
                hasActiveMessagesLoad: false
            ) == true
        )
    }

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
        #expect(recordedLimits == [240, 40])
    }

    @Test
    func sendMessageImmediatelyShowsOptimisticUserMessage() async {
        let loader = BlockingMessagesLoader()
        let sender = SuccessfulSender()
        let viewModel = DirectSessionViewModel(
            identity: makeIdentity(),
            loader: loader,
            sender: sender
        )

        let sent = await viewModel.sendMessage(
            "ship it",
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(sent == true)
        let optimisticTexts = viewModel.messages.compactMap { message in
            SessionTranscriptPresentationBuilder.make(from: message, dataEncryptionKey: nil)
                .entries
                .first(where: { $0.role == .user && $0.kind == .text })?
                .body
        }
        #expect(optimisticTexts.contains("ship it"))
    }

    @Test
    func sendMessageReconcilesOptimisticMessageAfterRefreshLoadsMatchingUserText() async throws {
        let loader = ReplacingMessagesLoader()
        let sender = SuccessfulSender()
        let viewModel = DirectSessionViewModel(
            identity: makeIdentity(),
            loader: loader,
            sender: sender
        )

        _ = await viewModel.sendMessage(
            "ship it",
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(viewModel.messages.map(\.id).contains(where: { $0.hasPrefix("optimistic:") }))

        try await Task.sleep(for: .milliseconds(350))

        #expect(viewModel.messages.map(\.id) == ["server-user"])
    }

    @Test
    func initialLoadRequestsTailFirstPageOfTwoHundredFortyMessages() async {
        let loader = RecordingMessagesLoader()
        let viewModel = DirectSessionViewModel(
            identity: makeIdentity(),
            loader: loader,
            sender: SuccessfulSender()
        )

        await viewModel.load(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(await loader.recordedLimits == [240])
    }

    @Test
    func loadOlderMessagesStopsWhenBackendRepeatsCursor() async {
        let loader = RepeatingOlderCursorLoader()
        let viewModel = DirectSessionViewModel(
            identity: makeIdentity(),
            loader: loader,
            sender: SuccessfulSender()
        )

        await viewModel.load(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )
        #expect(viewModel.hasOlderMessages == true)

        await viewModel.loadOlderMessages(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(viewModel.hasOlderMessages == false)
        #expect(await loader.recordedCursors == [nil, "cursor-1"])
    }

    @Test
    func olderMessagesLoadTriggerIDMatchesCursorUntilPaginationEnds() async {
        let loader = RepeatingOlderCursorLoader()
        let viewModel = DirectSessionViewModel(
            identity: makeIdentity(),
            loader: loader,
            sender: SuccessfulSender()
        )

        await viewModel.load(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(viewModel.olderMessagesLoadTriggerID == "cursor-1")

        await viewModel.loadOlderMessages(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(viewModel.olderMessagesLoadTriggerID == nil)
    }

    @Test
    func loadOlderMessagesPrependsOlderMessagesAheadOfCurrentPage() async {
        let loader = OlderMessagesPrependLoader()
        let viewModel = DirectSessionViewModel(
            identity: makeIdentity(),
            loader: loader,
            sender: SuccessfulSender()
        )

        await viewModel.load(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )
        #expect(viewModel.messages.map(\.id) == ["latest-1", "latest-2"])

        await viewModel.loadOlderMessages(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(viewModel.messages.map(\.id) == ["older-1", "older-2", "latest-1", "latest-2"])
        #expect(viewModel.hasOlderMessages == false)
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

private actor ReconnectingMessagesLoader: DirectSessionMessagesLoadingAction {
    func loadMessages(
        serverURLString: String,
        token: String,
        identity: DirectSessionIdentity,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        throw MachinesAPIError.rpcCallFailed("Machine data-plane socket is not connected")
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

private actor RepeatingOlderCursorLoader: DirectSessionMessagesLoadingAction {
    private(set) var recordedCursors: [String?] = []

    func loadMessages(
        serverURLString: String,
        token: String,
        identity: DirectSessionIdentity,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        recordedCursors.append(cursor)
        if cursor == nil {
            return APISessionMessagesPage(
                messages: [
                    APISessionMessage(
                        id: "latest",
                        seq: 2,
                        localId: nil,
                        content: APIEncryptedMessageContent(type: "text", payload: "{}"),
                        createdAt: 2,
                        updatedAt: 2
                    )
                ],
                nextCursor: "cursor-1",
                hasNext: true
            )
        }

        return APISessionMessagesPage(
            messages: [
                APISessionMessage(
                    id: "older",
                    seq: 1,
                    localId: nil,
                    content: APIEncryptedMessageContent(type: "text", payload: "{}"),
                    createdAt: 1,
                    updatedAt: 1
                )
            ],
            nextCursor: "cursor-1",
            hasNext: true
        )
    }
}

private actor OlderMessagesPrependLoader: DirectSessionMessagesLoadingAction {
    func loadMessages(
        serverURLString: String,
        token: String,
        identity: DirectSessionIdentity,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        if cursor == nil {
            return APISessionMessagesPage(
                messages: [
                    APISessionMessage(
                        id: "latest-1",
                        seq: 3,
                        localId: nil,
                        content: APIEncryptedMessageContent(type: "text", payload: "{}"),
                        createdAt: 3,
                        updatedAt: 3
                    ),
                    APISessionMessage(
                        id: "latest-2",
                        seq: 4,
                        localId: nil,
                        content: APIEncryptedMessageContent(type: "text", payload: "{}"),
                        createdAt: 4,
                        updatedAt: 4
                    ),
                ],
                nextCursor: "cursor-older",
                hasNext: true
            )
        }

        return APISessionMessagesPage(
            messages: [
                APISessionMessage(
                    id: "older-1",
                    seq: 1,
                    localId: nil,
                    content: APIEncryptedMessageContent(type: "text", payload: "{}"),
                    createdAt: 1,
                    updatedAt: 1
                ),
                APISessionMessage(
                    id: "older-2",
                    seq: 2,
                    localId: nil,
                    content: APIEncryptedMessageContent(type: "text", payload: "{}"),
                    createdAt: 2,
                    updatedAt: 2
                ),
            ],
            nextCursor: nil,
            hasNext: false
        )
    }
}

private actor ReplacingMessagesLoader: DirectSessionMessagesLoadingAction {
    private var callCount = 0

    func loadMessages(
        serverURLString: String,
        token: String,
        identity: DirectSessionIdentity,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        callCount += 1
        if callCount == 1 {
            return APISessionMessagesPage(messages: [], nextCursor: nil, hasNext: false)
        }

        return APISessionMessagesPage(
            messages: [
                APISessionMessage(
                    id: "server-user",
                    seq: 1,
                    localId: nil,
                    content: APIEncryptedMessageContent(
                        type: "json",
                        payload: sessionsMakeOptimisticUserPayload(text: "ship it")
                    ),
                    createdAt: 1,
                    updatedAt: 1
                )
            ],
            nextCursor: nil,
            hasNext: false
        )
    }
}
