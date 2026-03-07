import Foundation
import Combine
import Testing
@testable import FeatureSessions
import CoreKit

@MainActor
struct SessionsViewModelTests {
    @Test
    func loadSuccessPublishesSessions() async throws {
        let expected = [
            APISession(
                id: "s1",
                active: true,
                activeAt: 10,
                createdAt: 1,
                updatedAt: 11,
                metadataVersion: 2,
                metadata: "enc",
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let loader = MockSessionsLoader(result: .success(expected))
        let model = SessionsViewModel(
            loader: loader,
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: expected, nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([])),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.load(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(model.sessions.count == 1)
        #expect(model.errorMessage == nil)
        #expect(model.multiAgentInProgress == true)
    }

    @Test
    func loadWithoutTokenSetsValidationError() async throws {
        let model = SessionsViewModel(
            service: MockSessionsServiceForValidation()
        )

        await model.load(serverURLString: "https://api.unhappy.im", token: "")

        #expect(model.sessions.isEmpty)
        #expect(model.errorMessage == "API token is required")
        #expect(model.multiAgentInProgress == false)
    }

    @Test
    func loadWithInactiveSessionsMarksMultiAgentCompleted() async throws {
        let expected = [
            APISession(
                id: "s2",
                active: false,
                activeAt: 10,
                createdAt: 1,
                updatedAt: 11,
                metadataVersion: 2,
                metadata: "enc",
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let loader = MockSessionsLoader(result: .success(expected))
        let model = SessionsViewModel(
            loader: loader,
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: expected, nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([])),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.load(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(model.errorMessage == nil)
        #expect(model.multiAgentInProgress == false)
    }

    @Test
    func startPollingPublishesRowsFromPoller() async throws {
        let expected = [
            APISession(
                id: "poll",
                active: true,
                activeAt: 1,
                createdAt: 1,
                updatedAt: 3,
                metadataVersion: 1,
                metadata: "enc",
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: expected),
            messageLoader: MockSessionsMessagesLoader(result: .success([])),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.startPolling(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            interval: .seconds(60)
        )

        #expect(model.sessions == expected)
        #expect(model.errorMessage == nil)
        #expect(model.isLoading == false)
    }

    @Test
    func loadProjectsFailurePreservesExistingProjects() async throws {
        let existingProject = SessionMachineProject(
            machineID: "machine-1",
            machineDisplayName: "Work Mac",
            summary: APIMachineProjectSummary(
                path: "/repo/app",
                latestUpdatedAt: "2026-03-06T00:00:00.000Z",
                codexThreadCount: 1,
                claudeSessionCount: 0,
                openedExplicitly: true
            )
        )
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([])),
            projectsLoader: SequenceProjectsLoader(results: [.success([existingProject]), .failure(.failed)]),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.loadProjects(serverURLString: "https://api.unhappy.im", token: "token")
        await model.loadProjects(serverURLString: "https://api.unhappy.im", token: "token")

        #expect(model.projects.map(\.id) == [existingProject.id])
        #expect(model.projectsErrorMessage?.isEmpty == false)
    }

    @Test
    func loadUpstreamSessionsFailurePreservesExistingRows() async throws {
        let existingRow = SessionLinkedUpstreamSession(
            machineID: "machine-1",
            machineDisplayName: "Work Mac",
            summary: APIUpstreamSessionSummary(
                id: "thread-1",
                provider: .codex,
                title: "Remote",
                cwd: "/repo/app",
                updatedAt: "2026-03-06T03:00:00.000Z",
                createdAt: "2026-03-06T02:00:00.000Z",
                archived: false
            )
        )
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([])),
            upstreamSessionsLoader: SequenceUpstreamSessionsLoader(results: [.success([existingRow]), .failure(.failed)]),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.loadUpstreamSessions(serverURLString: "https://api.unhappy.im", token: "token")
        await model.loadUpstreamSessions(serverURLString: "https://api.unhappy.im", token: "token")

        #expect(model.upstreamSessions.map(\.id) == [existingRow.id])
        #expect(model.upstreamSessionsErrorMessage?.isEmpty == false)
    }

    @Test
    func loadFiltersAlreadyMirroredUpstreamSessions() async throws {
        let mirroredSession = APISession(
            id: "session-1",
            active: false,
            activeAt: 1,
            createdAt: 1,
            updatedAt: 3,
            metadataVersion: 1,
            metadata: #"{"machineId":"machine-1","flavor":"codex","agentSessionId":"thread-1"}"#,
            dataEncryptionKey: nil,
            lastMessage: nil
        )
        let upstreamRows = [
            SessionLinkedUpstreamSession(
                machineID: "machine-1",
                machineDisplayName: "Work Mac",
                summary: APIUpstreamSessionSummary(
                    id: "thread-1",
                    provider: .codex,
                    title: "Existing",
                    cwd: "/tmp/existing",
                    updatedAt: "2026-03-06T03:00:00.000Z",
                    createdAt: "2026-03-06T02:00:00.000Z",
                    archived: false
                )
            ),
            SessionLinkedUpstreamSession(
                machineID: "machine-1",
                machineDisplayName: "Work Mac",
                summary: APIUpstreamSessionSummary(
                    id: "thread-2",
                    provider: .codex,
                    title: "Fresh",
                    cwd: "/tmp/fresh",
                    updatedAt: "2026-03-06T04:00:00.000Z",
                    createdAt: "2026-03-06T03:00:00.000Z",
                    archived: false
                )
            )
        ]
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([mirroredSession])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [mirroredSession], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([])),
            upstreamSessionsLoader: MockUpstreamSessionsLoader(result: .success(upstreamRows)),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.load(serverURLString: "https://api.unhappy.im", token: "token")

        #expect(model.upstreamSessions.count == 1)
        #expect(model.upstreamSessions.first?.summary.id == "thread-2")
        #expect(model.upstreamSessionsErrorMessage == nil)
    }

    @Test
    func linkUpstreamSessionPublishesSuccessAndReloadsSessions() async throws {
        let reloadedSessions = [
            APISession(
                id: "linked-session",
                active: true,
                activeAt: 10,
                createdAt: 9,
                updatedAt: 11,
                metadataVersion: 1,
                metadata: "enc",
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let row = SessionLinkedUpstreamSession(
            machineID: "machine-1",
            machineDisplayName: "Work Mac",
            summary: APIUpstreamSessionSummary(
                id: "thread-9",
                provider: .codex,
                title: "Live Bugfix",
                cwd: "/tmp/live",
                updatedAt: "2026-03-06T04:00:00.000Z",
                createdAt: "2026-03-06T03:00:00.000Z",
                archived: false
            )
        )
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: reloadedSessions, nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([])),
            upstreamSessionLinker: MockUpstreamSessionLinker(
                result: .success(
                    APISessionSpawnResult(
                        success: true,
                        sessionID: "linked-session",
                        requiresUserApproval: nil,
                        actionRequired: nil,
                        directory: nil,
                        error: nil
                    )
                )
            ),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        _ = await model.linkUpstreamSession(
            row,
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(model.linkingUpstreamSessionID == nil)
        #expect(model.upstreamSessionStatusMessage == "Linked Codex session linked-session")
        #expect(model.sessions == reloadedSessions)
    }

    @Test
    func linkUpstreamSessionReusesExistingMirroredSessionWhenPresent() async throws {
        let mirroredSession = APISession(
            id: "mirrored-session",
            active: true,
            activeAt: 12,
            createdAt: 9,
            updatedAt: 20,
            metadataVersion: 1,
            metadata: #"{"machineId":"machine-1","flavor":"codex","agentSessionId":"thread-9","displayName":"Work Mac","cwd":"/tmp/live"}"#,
            dataEncryptionKey: nil,
            lastMessage: nil
        )
        let row = SessionLinkedUpstreamSession(
            machineID: "machine-1",
            machineDisplayName: "Work Mac",
            summary: APIUpstreamSessionSummary(
                id: "thread-9",
                provider: .codex,
                title: "Live Bugfix",
                cwd: "/tmp/live",
                updatedAt: "2026-03-06T04:00:00.000Z",
                createdAt: "2026-03-06T03:00:00.000Z",
                archived: false
            )
        )
        let linker = RecordingUpstreamSessionLinker(
            result: .success(
                APISessionSpawnResult(
                    success: true,
                    sessionID: "unexpected",
                    requiresUserApproval: nil,
                    actionRequired: nil,
                    directory: nil,
                    error: nil
                )
            )
        )
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([mirroredSession])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [mirroredSession], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([])),
            upstreamSessionLinker: linker,
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.load(serverURLString: "https://api.unhappy.im", token: "token")
        let linked = await model.linkUpstreamSession(
            row,
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(linked == "mirrored-session")
        #expect(model.upstreamSessionStatusMessage == "Opened existing Codex session")
        let recordedRequests = await linker.requests()
        #expect(recordedRequests.isEmpty)
    }

    @Test
    func loadMessagesSuccessPublishesSelectedSessionMessages() async throws {
        let message = APISessionMessage(
            id: "m1",
            seq: 1,
            localId: "l1",
            content: APIEncryptedMessageContent(type: "encrypted", payload: "abc"),
            createdAt: 10,
            updatedAt: 12
        )
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([message])),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.loadMessages(
            for: "session-1",
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(model.selectedSessionID == "session-1")
        #expect(model.selectedSessionMessages == [message])
        #expect(model.selectedSessionErrorMessage == nil)
    }

    @Test
    func removeProjectClearsTrackedProjectAfterSuccessfulClose() async throws {
        let project = SessionMachineProject(
            machineID: "machine-1",
            machineDisplayName: "Work Mac",
            summary: APIMachineProjectSummary(
                path: "/repo/app",
                latestUpdatedAt: "2026-03-06T00:00:00.000Z",
                codexThreadCount: 1,
                claudeSessionCount: 0,
                openedExplicitly: true
            )
        )
        let projectsLoader = SequenceProjectsLoader(
            results: [
                .success([project]),
                .success([project]),
            ]
        )
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([])),
            projectsLoader: projectsLoader,
            projectRemover: MockProjectRemover(result: .success(project)),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.load(serverURLString: "https://api.unhappy.im", token: "token")
        #expect(model.projects.map(\.id) == ["machine-1|/repo/app"])

        await model.removeProject(
            machineID: "machine-1",
            projectPath: "/repo/app",
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(model.projects.isEmpty)
        #expect(model.removingProjectID == nil)
        #expect(model.projectsErrorMessage == nil)
    }

    @Test
    func loadFirstMessagePreviewReturnsEarliestReadableMessage() async throws {
        let messages = [
            APISessionMessage(
                id: "m2",
                seq: 2,
                localId: nil,
                content: APIEncryptedMessageContent(type: "text", payload: "Second message"),
                createdAt: 2,
                updatedAt: 2
            ),
            APISessionMessage(
                id: "m1",
                seq: 1,
                localId: nil,
                content: APIEncryptedMessageContent(type: "text", payload: "First message"),
                createdAt: 1,
                updatedAt: 1
            ),
        ]
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success(messages)),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        let preview = await model.loadFirstMessagePreview(
            for: "session-1",
            dataEncryptionKey: nil,
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(preview == "First message")
    }

    @Test
    func sendMessageSuccessSkipsReloadAndAppendsOptimisticMessage() async throws {
        let existingMessage = APISessionMessage(
            id: "m1",
            seq: 1,
            localId: nil,
            content: APIEncryptedMessageContent(type: "encrypted", payload: "first"),
            createdAt: 1,
            updatedAt: 1
        )
        let messageLoader = SequenceMessagesLoader(messagesByCall: [[existingMessage], [existingMessage]])
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: messageLoader,
            messageSender: MockSessionMessageSender(result: .success(APISessionSendMessageResult(success: true, queueCount: nil, queuedMessages: nil, error: nil))),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.loadMessages(
            for: "session-1",
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )
        #expect(await messageLoader.loadCallCount() == 1)

        let sent = await model.sendMessage(
            for: "session-1",
            text: "hello optimistic",
            steerMode: .queue,
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(sent == true)
        #expect(await messageLoader.loadCallCount() == 1)
        #expect(model.selectedSessionMessages.count == 2)
        #expect(model.selectedSessionMessages.last?.id.hasPrefix("optimistic-") == true)
        #expect(model.selectedSessionMessages.last?.localId == model.selectedSessionMessages.last?.id)
        #expect(model.selectedSessionMessages.last?.content?.type == "optimistic-user")
        #expect(model.selectedSessionMessages.last?.content?.payload.contains("\"role\":\"user\"") == true)
        #expect(model.selectedSessionMessages.last?.content?.payload.contains("hello optimistic") == true)
    }

    @Test
    func selectedSessionMessagePollingUpdatesWhenMessagesChange() async throws {
        let message1 = APISessionMessage(
            id: "m1",
            seq: 1,
            localId: nil,
            content: APIEncryptedMessageContent(type: "encrypted", payload: "first"),
            createdAt: 1,
            updatedAt: 1
        )
        let message2 = APISessionMessage(
            id: "m2",
            seq: 2,
            localId: nil,
            content: APIEncryptedMessageContent(type: "encrypted", payload: "second"),
            createdAt: 2,
            updatedAt: 2
        )

        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: SequenceMessagesLoader(messagesByCall: [[message1], [message1, message2]]),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        model.startSelectedSessionMessagesPolling(
            for: "session-1",
            serverURLString: "https://api.unhappy.im",
            token: "token",
            interval: .milliseconds(20)
        )

        try await Task.sleep(for: .milliseconds(120))
        model.stopSelectedSessionMessagesPolling()

        #expect(model.selectedSessionMessages == [message1, message2])
    }

    @Test
    func selectedSessionMessagePollingDoesNotChurnWhenMessagesUnchanged() async throws {
        let message = APISessionMessage(
            id: "m1",
            seq: 1,
            localId: nil,
            content: APIEncryptedMessageContent(type: "encrypted", payload: "stable"),
            createdAt: 1,
            updatedAt: 1
        )

        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([message])),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        var publishCountForStablePayload = 0
        let cancellable = model.$selectedSessionMessages.sink { messages in
            if messages == [message] {
                publishCountForStablePayload += 1
            }
        }

        model.startSelectedSessionMessagesPolling(
            for: "session-1",
            serverURLString: "https://api.unhappy.im",
            token: "token",
            interval: .milliseconds(20)
        )

        try await Task.sleep(for: .milliseconds(120))
        model.stopSelectedSessionMessagesPolling()
        cancellable.cancel()

        #expect(model.selectedSessionMessages == [message])
        #expect(publishCountForStablePayload == 1)
    }

    @Test
    func stopSelectedSessionMessagePollingClearsTaskState() async throws {
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([])),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        model.startSelectedSessionMessagesPolling(
            for: "session-1",
            serverURLString: "https://api.unhappy.im",
            token: "token",
            interval: .seconds(1)
        )
        #expect(model.isSelectedSessionMessagesPolling == true)

        model.stopSelectedSessionMessagesPolling()
        #expect(model.isSelectedSessionMessagesPolling == false)
    }

    @Test
    func deleteSessionRemovesSessionFromList() async throws {
        let sessions = [
            APISession(
                id: "s1",
                active: false,
                activeAt: 10,
                createdAt: 1,
                updatedAt: 11,
                metadataVersion: 2,
                metadata: "enc",
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success(sessions)),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: sessions, nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([])),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.load(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )
        await model.deleteSession(
            sessionID: "s1",
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(model.sessions.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test
    func deleteSessionRunsKillBeforeDeleteWhenKillerIsProvided() async throws {
        let sessions = [
            APISession(
                id: "s1",
                active: false,
                activeAt: 10,
                createdAt: 1,
                updatedAt: 11,
                metadataVersion: 2,
                metadata: "enc",
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let recorder = CallOrderRecorder()
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success(sessions)),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: sessions, nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([])),
            preDeleteKiller: RecordingSessionPreDeleteKillUseCase(recorder: recorder),
            deleteUseCase: RecordingSessionDeleteUseCase(recorder: recorder),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.load(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )
        await model.deleteSession(
            sessionID: "s1",
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        let calls = await recorder.snapshot()
        #expect(calls == ["kill:s1", "delete:s1"])
        #expect(model.sessions.isEmpty)
    }

    @Test
    func messageCacheIsBoundedToPreventUnboundedGrowth() async throws {
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: SessionAwareMessagesLoader(),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        for idx in 1...8 {
            await model.loadMessages(
                for: "session-\(idx)",
                serverURLString: "https://api.unhappy.im",
                token: "token"
            )
        }

        #expect(model.cachedSessionMessagesCount == 4)
    }

    @Test
    func loadMessagesTrimsPerSessionMessageCount() async throws {
        let overLimitMessages = (1...200).map { idx in
            APISessionMessage(
                id: "m\(idx)",
                seq: idx,
                localId: nil,
                content: APIEncryptedMessageContent(type: "encrypted", payload: "\(idx)"),
                createdAt: TimeInterval(idx),
                updatedAt: TimeInterval(idx)
            )
        }
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success(overLimitMessages)),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.loadMessages(
            for: "session-over-limit",
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(model.selectedSessionMessages.count == 150)
        #expect(model.selectedSessionMessages.first?.seq == 51)
        #expect(model.selectedSessionMessages.last?.seq == 200)
    }

    @Test
    func loadMessagesIncrementalRefreshStillRespectsPerSessionMessageLimit() async throws {
        let firstBatch = (1...150).map { idx in
            APISessionMessage(
                id: "m\(idx)",
                seq: idx,
                localId: nil,
                content: APIEncryptedMessageContent(type: "encrypted", payload: "\(idx)"),
                createdAt: TimeInterval(idx),
                updatedAt: TimeInterval(idx)
            )
        }
        let secondBatch = (1...151).map { idx in
            APISessionMessage(
                id: "m\(idx)",
                seq: idx,
                localId: nil,
                content: APIEncryptedMessageContent(type: "encrypted", payload: "\(idx)"),
                createdAt: TimeInterval(idx),
                updatedAt: TimeInterval(idx)
            )
        }

        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: SequenceMessagesLoader(messagesByCall: [firstBatch, secondBatch]),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.loadMessages(
            for: "session-1",
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )
        await model.loadMessages(
            for: "session-1",
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(model.selectedSessionMessages.count == 150)
        #expect(model.selectedSessionMessages.first?.seq == 2)
        #expect(model.selectedSessionMessages.last?.seq == 151)
    }

    @Test
    func loadMoreAppendsNextPageRows() async throws {
        let firstPageRows = [
            APISession(
                id: "s2",
                active: false,
                activeAt: 1,
                createdAt: 1,
                updatedAt: 20,
                metadataVersion: 1,
                metadata: "enc",
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let secondPageRows = [
            APISession(
                id: "s1",
                active: false,
                activeAt: 1,
                createdAt: 1,
                updatedAt: 10,
                metadataVersion: 1,
                metadata: "enc",
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let pageLoader = SequenceSessionsPageLoader(results: [
            .init(sessions: firstPageRows, nextCursor: "next", hasNext: true),
            .init(sessions: secondPageRows, nextCursor: nil, hasNext: false)
        ])
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success(firstPageRows)),
            pageLoader: pageLoader,
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([])),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.load(serverURLString: "https://api.unhappy.im", token: "token")
        await model.loadMoreSessions(serverURLString: "https://api.unhappy.im", token: "token")

        #expect(model.sessions.map(\.id) == ["s2", "s1"])
        #expect(model.hasMoreSessions == false)
    }

    @Test
    func setSessionTitleUpdatesSessionDisplayName() async throws {
        let sessions = [
            APISession(
                id: "session-1",
                active: false,
                activeAt: 1,
                createdAt: 1,
                updatedAt: 10,
                metadataVersion: 1,
                metadata: "enc",
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success(sessions)),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: sessions, nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([])),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.load(serverURLString: "https://api.unhappy.im", token: "token")
        await model.setSessionTitle(
            sessionID: "session-1",
            title: "New Title",
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(model.sessions.first?.displayName == "New Title")
        #expect(model.errorMessage == nil)
    }

    @Test
    func takeQueuedComposerDraftRemovesPickedEntry() async throws {
        let sessions = [
            APISession(
                id: "session-1",
                active: false,
                activeAt: 1,
                createdAt: 1,
                updatedAt: 10,
                metadataVersion: 1,
                metadata: "enc",
                agentState: nil,
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success(sessions)),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: sessions, nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([])),
            messageSender: MockSessionMessageSender(result: .success(APISessionSendMessageResult(success: true, queueCount: nil, queuedMessages: nil, error: nil))),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.load(serverURLString: "https://api.unhappy.im", token: "token")
        _ = await model.enqueueComposerDraft(
            for: "session-1",
            text: "first",
            attachments: [],
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )
        _ = await model.enqueueComposerDraft(
            for: "session-1",
            text: "second",
            attachments: [],
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(model.queuedComposerMessages(for: "session-1") == ["second"])
        let taken = model.takeQueuedComposerDraft(for: "session-1", at: 0)
        #expect(taken?.text == "second")
        #expect(model.queuedComposerMessages(for: "session-1").isEmpty)
    }

    @Test
    func messagesForSessionReadsSessionScopedCacheWithoutBleedingSelectedTranscript() async throws {
        let selectedSessionMessage = APISessionMessage(
            id: "selected-message",
            seq: 1,
            localId: nil,
            content: APIEncryptedMessageContent(type: "encrypted", payload: "selected"),
            createdAt: 1,
            updatedAt: 1
        )
        let otherSessionMessage = APISessionMessage(
            id: "other-message",
            seq: 1,
            localId: nil,
            content: APIEncryptedMessageContent(type: "encrypted", payload: "other"),
            createdAt: 2,
            updatedAt: 2
        )
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            messageLoader: SessionMappedMessagesLoader(
                rowsBySessionID: [
                    "selected-session": [selectedSessionMessage],
                    "other-session": [otherSessionMessage]
                ]
            ),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        await model.loadMessages(
            for: "selected-session",
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )
        await model.loadMessages(
            for: "other-session",
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(model.messages(for: "selected-session") == [selectedSessionMessage])
        #expect(model.messages(for: "other-session") == [otherSessionMessage])
    }

    func refreshAndSelectSessionLoadsSpawnedSessionIntoDetailState() async throws {
        let spawnedSession = APISession(
            id: "spawned-session",
            active: true,
            activeAt: 10,
            createdAt: 9,
            updatedAt: 11,
            metadataVersion: 1,
            metadata: "enc",
            dataEncryptionKey: nil,
            lastMessage: nil
        )
        let spawnedMessage = APISessionMessage(
            id: "message-1",
            seq: 1,
            localId: nil,
            content: APIEncryptedMessageContent(type: "encrypted", payload: "payload"),
            createdAt: 10,
            updatedAt: 10
        )
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(
                result: .success(
                    .init(
                        sessions: [spawnedSession],
                        nextCursor: nil,
                        hasNext: false
                    )
                )
            ),
            poller: MockSessionsPoller(rows: []),
            messageLoader: MockSessionsMessagesLoader(result: .success([spawnedMessage])),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(())),
            titleUseCase: MockSessionTitleUseCase(result: .success(()))
        )

        let resolved = await model.refreshAndSelectSession(
            sessionID: "spawned-session",
            serverURLString: "https://api.unhappy.im",
            token: "token",
            maxAttempts: 1
        )

        #expect(resolved?.id == "spawned-session")
        #expect(model.selectedSessionID == "spawned-session")
        #expect(model.selectedSessionMessages == [spawnedMessage])
        #expect(model.selectedSessionErrorMessage == nil)
    }
}
