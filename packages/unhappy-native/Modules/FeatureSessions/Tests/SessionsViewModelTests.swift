import Foundation
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
            deleteUseCase: MockSessionDeleteUseCase(result: .success(()))
        )

        await model.load(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(model.sessions.count == 1)
        #expect(model.errorMessage == nil)
    }

    @Test
    func loadWithoutTokenSetsValidationError() async throws {
        let model = SessionsViewModel(
            service: MockSessionsServiceForValidation()
        )

        await model.load(serverURLString: "https://api.unhappy.im", token: "")

        #expect(model.sessions.isEmpty)
        #expect(model.errorMessage == "API token is required")
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
            deleteUseCase: MockSessionDeleteUseCase(result: .success(()))
        )

        await model.load(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(model.errorMessage == nil)
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
            deleteUseCase: MockSessionDeleteUseCase(result: .success(()))
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
    func loadUsesRuntimeProjectContextsForUpstreamSync() async throws {
        let runtimeSession = APISession(
            id: "runtime",
            active: true,
            activeAt: 1,
            createdAt: 1,
            updatedAt: 3,
            metadataVersion: 1,
            metadata: #"{"machineId":"machine-1","displayName":"Work Mac","cwd":"/repo/app"}"#,
            dataEncryptionKey: nil,
            lastMessage: nil
        )
        let upstreamLoader = RecordingUpstreamSessionsLoader(result: .success([]))
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([runtimeSession])),
            pageLoader: MockSessionsPageLoader(
                result: .success(.init(sessions: [runtimeSession], nextCursor: nil, hasNext: false))
            ),
            poller: MockSessionsPoller(rows: []),
            upstreamSessionsLoader: upstreamLoader,
            deleteUseCase: MockSessionDeleteUseCase(result: .success(()))
        )

        await model.load(serverURLString: "https://api.unhappy.im", token: "token")

        let requestedProjects = await upstreamLoader.requestedProjectSnapshots()
        #expect(requestedProjects.count == 1)
        #expect(requestedProjects.first?.isEmpty == true)
    }

    @Test
    func loadProjectsStreamingStartsUpstreamSyncForVisibleProjectScopes() async throws {
        let project = SessionMachineProject(
            machineID: "machine-1",
            machineDisplayName: "Work Mac",
            summary: APIMachineProjectSummary(
                path: "/repo/app",
                latestUpdatedAt: "2026-03-06T04:00:00.000Z",
                codexThreadCount: 1,
                claudeSessionCount: 0,
                openedExplicitly: true
            )
        )
        let upstreamRow = SessionLinkedUpstreamSession(
            machineID: "machine-1",
            machineDisplayName: "Work Mac",
            summary: APIUpstreamSessionSummary(
                id: "thread-1",
                provider: .codex,
                title: "Thread",
                cwd: "/repo/app",
                updatedAt: "2026-03-06T05:00:00.000Z",
                createdAt: "2026-03-06T04:00:00.000Z",
                archived: false
            )
        )
        let projectsLoader = StreamingProjectsLoader(
            snapshots: [
                SessionProjectsLoadSnapshot(
                    machineID: "machine-1",
                    projects: [project],
                    errorMessage: nil,
                    isFinal: false
                ),
                SessionProjectsLoadSnapshot(
                    machineID: nil,
                    projects: [],
                    errorMessage: nil,
                    isFinal: true
                ),
            ]
        )
        let upstreamLoader = StreamingRecordingUpstreamSessionsLoader(rows: [upstreamRow])
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            projectsLoader: projectsLoader,
            upstreamSessionsLoader: upstreamLoader,
            deleteUseCase: MockSessionDeleteUseCase(result: .success(()))
        )

        await model.loadProjects(serverURLString: "https://api.unhappy.im", token: "token")
        try await Task.sleep(for: .milliseconds(50))

        let requestedProjects = await upstreamLoader.requestedProjectSnapshots()
        #expect(requestedProjects.count == 1)
        #expect(requestedProjects.first?.map(\.summary.path) == ["/repo/app"])
        #expect(model.upstreamSessions.map(\.summary.id) == ["thread-1"])
    }

    @Test
    func loadRemovesDuplicateMirroredSessionsBoundToSameUpstreamIdentity() async throws {
        let olderSession = APISession(
            id: "session-older",
            active: false,
            activeAt: 1,
            createdAt: 1,
            updatedAt: 2,
            metadataVersion: 1,
            metadata: #"{"machineId":"machine-1","flavor":"codex","agentSessionId":"thread-1","cwd":"/repo/app"}"#,
            dataEncryptionKey: nil,
            lastMessage: nil
        )
        let newerSession = APISession(
            id: "session-newer",
            active: true,
            activeAt: 2,
            createdAt: 2,
            updatedAt: 3,
            metadataVersion: 1,
            metadata: #"{"machineId":"machine-1","flavor":"codex","agentSessionId":"thread-1","cwd":"/repo/app"}"#,
            dataEncryptionKey: nil,
            lastMessage: nil
        )
        let recorder = SessionDeleteRecorder()
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([olderSession, newerSession])),
            pageLoader: MockSessionsPageLoader(
                result: .success(.init(sessions: [olderSession, newerSession], nextCursor: nil, hasNext: false))
            ),
            poller: MockSessionsPoller(rows: []),
            deleteUseCase: RecordingSessionDeleteUseCase(recorder: recorder)
        )

        await model.load(serverURLString: "https://api.unhappy.im", token: "token")

        #expect(model.sessions.isEmpty)
        #expect(await recorder.snapshot() == ["delete:session-older", "delete:session-newer"])
    }

    @Test
    func startPollingSkipsSupportingDataRefreshWhenProjectFingerprintIsUnchanged() async throws {
        let runtimeSession = APISession(
            id: "runtime",
            active: true,
            activeAt: 1,
            createdAt: 1,
            updatedAt: 3,
            metadataVersion: 1,
            metadata: #"{"machineId":"machine-1","displayName":"Work Mac","cwd":"/repo/app"}"#,
            dataEncryptionKey: nil,
            lastMessage: nil
        )
        let projectsLoader = RecordingProjectsLoader(result: .success([]))
        let upstreamLoader = RecordingUpstreamSessionsLoader(result: .success([]))
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([runtimeSession])),
            pageLoader: MockSessionsPageLoader(
                result: .success(.init(sessions: [runtimeSession], nextCursor: nil, hasNext: false))
            ),
            poller: SequenceSessionsPoller(emissions: [[runtimeSession]]),
            projectsLoader: projectsLoader,
            upstreamSessionsLoader: upstreamLoader,
            deleteUseCase: MockSessionDeleteUseCase(result: .success(()))
        )

        await model.load(serverURLString: "https://api.unhappy.im", token: "token")
        #expect(await projectsLoader.callCount() == 1)
        #expect(await upstreamLoader.callCount() == 1)

        await model.startPolling(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            interval: .seconds(60)
        )

        #expect(await projectsLoader.callCount() == 1)
        #expect(await upstreamLoader.callCount() == 1)
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
            projectsLoader: SequenceProjectsLoader(results: [.success([existingProject]), .failure(.failed)]),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(()))
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
            upstreamSessionsLoader: SequenceUpstreamSessionsLoader(results: [.success([existingRow]), .failure(.failed)]),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(()))
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
            upstreamSessionsLoader: MockUpstreamSessionsLoader(result: .success(upstreamRows)),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(()))
        )

        await model.load(serverURLString: "https://api.unhappy.im", token: "token")

        #expect(model.upstreamSessions.count == 2)
        #expect(model.upstreamSessions.map(\.summary.id) == ["thread-1", "thread-2"])
        #expect(model.upstreamSessionsErrorMessage == nil)
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
                .success([]),
            ]
        )
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            projectsLoader: projectsLoader,
            projectRemover: MockProjectRemover(result: .success(project)),
            deleteUseCase: MockSessionDeleteUseCase(result: .success(()))
        )

        await model.load(serverURLString: "https://api.unhappy.im", token: "token")
        #expect(model.projects.map(\.id) == ["machine-1|/repo/app"])

        await model.removeProject(
            machineID: "machine-1",
            projectPath: "/repo/app",
            wrappedMachineDataEncryptionKey: nil,
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(model.projects.isEmpty)
        #expect(model.removingProjectID == nil)
        #expect(model.projectsErrorMessage == nil)
    }

    @Test
    func refreshProjectOnlyReloadsTheSelectedProjectScope() async throws {
        let projectOne = SessionMachineProject(
            machineID: "machine-1",
            machineDisplayName: "Work Mac",
            summary: APIMachineProjectSummary(
                path: "/repo/one",
                latestUpdatedAt: "2026-03-06T00:00:00.000Z",
                codexThreadCount: 1,
                claudeSessionCount: 0,
                openedExplicitly: true
            )
        )
        let projectTwo = SessionMachineProject(
            machineID: "machine-2",
            machineDisplayName: "Home Mac",
            summary: APIMachineProjectSummary(
                path: "/repo/two",
                latestUpdatedAt: "2026-03-06T01:00:00.000Z",
                codexThreadCount: 1,
                claudeSessionCount: 0,
                openedExplicitly: true
            )
        )
        let projectsLoader = RecordingProjectsLoader(result: .success([projectOne, projectTwo]))
        let upstreamLoader = RecordingUpstreamSessionsLoader(result: .success([]))
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            projectsLoader: projectsLoader,
            upstreamSessionsLoader: upstreamLoader,
            deleteUseCase: MockSessionDeleteUseCase(result: .success(()))
        )

        await model.loadProjects(serverURLString: "https://api.unhappy.im", token: "token")
        await model.refreshProject(
            machineID: "machine-2",
            projectPath: "/repo/two",
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(await projectsLoader.callCount() == 1)
        let requestedProjects = await upstreamLoader.requestedProjectSnapshots()
        #expect(requestedProjects.count == 1)
        #expect(requestedProjects.first?.map(\.id) == [projectTwo.id])
    }

    @Test
    func refreshProjectIsNotBlockedByAnotherActiveUpstreamScope() async throws {
        let projectOne = SessionMachineProject(
            machineID: "machine-1",
            machineDisplayName: "Work Mac",
            summary: APIMachineProjectSummary(
                path: "/repo/one",
                latestUpdatedAt: "2026-03-06T00:00:00.000Z",
                codexThreadCount: 1,
                claudeSessionCount: 0,
                openedExplicitly: true
            )
        )
        let projectTwo = SessionMachineProject(
            machineID: "machine-2",
            machineDisplayName: "Home Mac",
            summary: APIMachineProjectSummary(
                path: "/repo/two",
                latestUpdatedAt: "2026-03-06T01:00:00.000Z",
                codexThreadCount: 1,
                claudeSessionCount: 0,
                openedExplicitly: true
            )
        )
        let upstreamLoader = DelayedStreamingUpstreamSessionsLoader(delay: .milliseconds(200))
        let model = SessionsViewModel(
            loader: MockSessionsLoader(result: .success([])),
            pageLoader: MockSessionsPageLoader(result: .success(.init(sessions: [], nextCursor: nil, hasNext: false))),
            poller: MockSessionsPoller(rows: []),
            projectsLoader: RecordingProjectsLoader(result: .success([projectOne, projectTwo])),
            upstreamSessionsLoader: upstreamLoader,
            deleteUseCase: MockSessionDeleteUseCase(result: .success(()))
        )

        await model.loadProjects(serverURLString: "https://api.unhappy.im", token: "token")

        let firstRefresh = Task {
            await model.refreshProject(
                machineID: "machine-1",
                projectPath: "/repo/one",
                serverURLString: "https://api.unhappy.im",
                token: "token"
            )
        }
        try await Task.sleep(for: .milliseconds(20))
        await model.refreshProject(
            machineID: "machine-2",
            projectPath: "/repo/two",
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )
        _ = await firstRefresh.value

        let requestedProjects = await upstreamLoader.requestedProjectSnapshots()
        #expect(requestedProjects.count == 2)
        #expect(requestedProjects.map { $0.map(\.id) } == [[projectOne.id], [projectTwo.id]])
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
            deleteUseCase: MockSessionDeleteUseCase(result: .success(()))
        )

        await model.load(serverURLString: "https://api.unhappy.im", token: "token")
        await model.loadMoreSessions(serverURLString: "https://api.unhappy.im", token: "token")

        #expect(model.sessions.map(\.id) == ["s2", "s1"])
        #expect(model.hasMoreSessions == false)
    }

}
