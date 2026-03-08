import Testing
@testable import FeatureSessions
import CoreKit

struct SessionListPresentationTests {
    @Test
    func projectGroupsClusterSessionsByMachineAndProjectPath() {
        let mirroredSession = APISession(
            id: "session-1",
            active: true,
            activeAt: 10,
            createdAt: 1,
            updatedAt: 20,
            metadataVersion: 1,
            metadata: #"{"machineId":"machine-1","flavor":"codex","agentSessionId":"thread-1","displayName":"Work Mac","cwd":"/repo/app"}"#,
            dataEncryptionKey: nil,
            lastMessage: nil
        )
        let mirroredSessionTwo = APISession(
            id: "session-2",
            active: false,
            activeAt: 10,
            createdAt: 1,
            updatedAt: 18,
            metadataVersion: 1,
            metadata: #"{"machineId":"machine-1","flavor":"claude","agentSessionId":"claude-1","displayName":"Work Mac","cwd":"/repo/app"}"#,
            dataEncryptionKey: nil,
            lastMessage: nil
        )
        let upstreamRow = SessionLinkedUpstreamSession(
            machineID: "machine-1",
            machineDisplayName: "Work Mac",
            summary: APIUpstreamSessionSummary(
                id: "thread-2",
                provider: .codex,
                title: "Remote Only",
                cwd: "/repo/app",
                updatedAt: "2026-03-06T04:00:00.000Z",
                createdAt: "2026-03-06T03:00:00.000Z",
                archived: false
            )
        )

        let groups = SessionListPresentationBuilder.projectGroups(
            sessions: [mirroredSession, mirroredSessionTwo],
            upstreamSessions: [upstreamRow],
            projects: [
                SessionMachineProject(
                    machineID: "machine-1",
                    machineDisplayName: "Work Mac",
                    summary: APIMachineProjectSummary(
                        path: "/repo/app",
                        latestUpdatedAt: "2026-03-06T05:00:00.000Z",
                        codexThreadCount: 3,
                        claudeSessionCount: 0,
                        openedExplicitly: true
                    )
                )
            ]
        )

        #expect(groups.count == 1)
        #expect(groups.first?.machineID == "machine-1")
        #expect(groups.first?.projectPath == "/repo/app")
        #expect(groups.first?.hasConcreteProjectPath == true)
        #expect(groups.first?.title == "app")
        #expect(groups.first?.mirroredSessions.map(\.id) == ["session-1", "session-2"])
        #expect(groups.first?.upstreamSessions.map(\.summary.id) == ["thread-2"])
        #expect(groups.first?.activeSessionCount == 1)
        #expect(groups.first?.allSessionCount == 3)
    }

    @Test
    func projectGroupsIncludeBookmarkedProjectWithoutExistingSessions() {
        let groups = SessionListPresentationBuilder.projectGroups(
            sessions: [],
            upstreamSessions: [],
            projects: [
                SessionMachineProject(
                    machineID: "machine-1",
                    machineDisplayName: "Work Mac",
                    summary: APIMachineProjectSummary(
                        path: "/repo/app",
                        latestUpdatedAt: "2026-03-06T00:00:00.000Z",
                        codexThreadCount: 0,
                        claudeSessionCount: 0,
                        openedExplicitly: true
                    )
                )
            ]
        )

        #expect(groups.count == 1)
        #expect(groups.first?.machineID == "machine-1")
        #expect(groups.first?.projectPath == "/repo/app")
        #expect(groups.first?.allSessionCount == 0)
    }

    @Test
    func projectGroupsIncludeRuntimeSessionPathsWithoutExplicitProjects() {
        let mirroredSession = APISession(
            id: "session-1",
            active: true,
            activeAt: 10,
            createdAt: 1,
            updatedAt: 20,
            metadataVersion: 1,
            metadata: #"{"machineId":"machine-1","flavor":"codex","agentSessionId":"thread-1","displayName":"Work Mac","cwd":"/repo/app"}"#,
            dataEncryptionKey: nil,
            lastMessage: nil
        )

        let groups = SessionListPresentationBuilder.projectGroups(
            sessions: [mirroredSession],
            upstreamSessions: [],
            projects: []
        )

        #expect(groups.count == 1)
        #expect(groups.first?.machineID == "machine-1")
        #expect(groups.first?.projectPath == "/repo/app")
        #expect(groups.first?.displayMirroredSessions.map(\.id) == ["session-1"])
    }

    @Test
    func projectGroupsMatchHomeRelativeSessionPathToAbsoluteProject() {
        let mirroredSession = APISession(
            id: "session-1",
            active: true,
            activeAt: 10,
            createdAt: 1,
            updatedAt: 20,
            metadataVersion: 1,
            metadata: #"{"machineId":"machine-1","displayName":"Work Mac","path":"~/Downloads/unhappy","homeDir":"/Users/skyline23"}"#,
            dataEncryptionKey: nil,
            lastMessage: nil
        )

        let groups = SessionListPresentationBuilder.projectGroups(
            sessions: [mirroredSession],
            upstreamSessions: [],
            projects: [
                SessionMachineProject(
                    machineID: "machine-1",
                    machineDisplayName: "Work Mac",
                    summary: APIMachineProjectSummary(
                        path: "/Users/skyline23/Downloads/unhappy",
                        latestUpdatedAt: "2026-03-07T00:00:00.000Z",
                        codexThreadCount: 1,
                        claudeSessionCount: 0,
                        openedExplicitly: true
                    )
                )
            ]
        )

        #expect(groups.count == 1)
        #expect(groups.first?.projectPath == "/Users/skyline23/Downloads/unhappy")
        #expect(groups.first?.mirroredSessions.map(\.id) == ["session-1"])
    }

    @Test
    func projectGroupResolvesUpdatedRowsForExistingID() {
        let project = SessionMachineProject(
            machineID: "machine-1",
            machineDisplayName: "Work Mac",
            summary: APIMachineProjectSummary(
                path: "/repo/app",
                latestUpdatedAt: "2026-03-07T00:00:00.000Z",
                codexThreadCount: 0,
                claudeSessionCount: 0,
                openedExplicitly: true
            )
        )
        let initialGroup = SessionListPresentationBuilder.projectGroups(
            sessions: [],
            upstreamSessions: [],
            projects: [project]
        ).first

        let upstreamRow = SessionLinkedUpstreamSession(
            machineID: "machine-1",
            machineDisplayName: "Work Mac",
            summary: APIUpstreamSessionSummary(
                id: "thread-1",
                provider: .codex,
                title: "Remote",
                cwd: "/repo/app",
                updatedAt: "2026-03-07T01:00:00.000Z",
                createdAt: "2026-03-07T00:30:00.000Z",
                archived: false
            )
        )

        let resolvedGroup = SessionListPresentationBuilder.projectGroup(
            id: initialGroup?.id ?? "",
            sessions: [],
            upstreamSessions: [upstreamRow],
            projects: [project]
        )

        #expect(resolvedGroup?.upstreamSessions.map(\.summary.id) == ["thread-1"])
    }

    @Test
    func projectGroupsCollapseMirroredDuplicatesAndMatchingUpstreamRows() {
        let olderMirroredSession = APISession(
            id: "session-1",
            active: false,
            activeAt: 10,
            createdAt: 1,
            updatedAt: 18,
            metadataVersion: 1,
            metadata: #"{"machineId":"machine-1","flavor":"codex","agentSessionId":"thread-1","displayName":"Work Mac","cwd":"/repo/app"}"#,
            dataEncryptionKey: nil,
            lastMessage: nil
        )
        let newerMirroredSession = APISession(
            id: "session-2",
            active: true,
            activeAt: 11,
            createdAt: 2,
            updatedAt: 22,
            metadataVersion: 1,
            metadata: #"{"machineId":"machine-1","flavor":"codex","agentSessionId":"thread-1","displayName":"Work Mac","cwd":"/repo/app"}"#,
            dataEncryptionKey: nil,
            lastMessage: nil
        )
        let matchingUpstreamRow = SessionLinkedUpstreamSession(
            machineID: "machine-1",
            machineDisplayName: "Work Mac",
            summary: APIUpstreamSessionSummary(
                id: "thread-1",
                provider: .codex,
                title: "Remote Live",
                cwd: "/repo/app",
                updatedAt: "2026-03-06T05:00:00.000Z",
                createdAt: "2026-03-06T03:00:00.000Z",
                archived: false
            )
        )

        let groups = SessionListPresentationBuilder.projectGroups(
            sessions: [olderMirroredSession, newerMirroredSession],
            upstreamSessions: [matchingUpstreamRow],
            projects: [
                SessionMachineProject(
                    machineID: "machine-1",
                    machineDisplayName: "Work Mac",
                    summary: APIMachineProjectSummary(
                        path: "/repo/app",
                        latestUpdatedAt: "2026-03-06T05:00:00.000Z",
                        codexThreadCount: 1,
                        claudeSessionCount: 0,
                        openedExplicitly: true
                    )
                )
            ]
        )

        #expect(groups.count == 1)
        #expect(groups.first?.displayMirroredSessions.isEmpty == true)
        #expect(groups.first?.displayUpstreamSessions.map(\.summary.id) == ["thread-1"])
        #expect(groups.first?.activeSessionCount == 0)
        #expect(groups.first?.allSessionCount == 1)
    }
}
