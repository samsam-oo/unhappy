import Testing
@testable import FeatureSessions
import CoreKit

struct SessionListPresentationTests {
    @Test
    func machineEntriesIncludeMirroredAndUnlinkedUpstreamSessions() {
        let mirroredSession = APISession(
            id: "session-1",
            active: true,
            activeAt: 10,
            createdAt: 1,
            updatedAt: 20,
            metadataVersion: 1,
            metadata: #"{"machineId":"machine-1","flavor":"codex","agentSessionId":"thread-1","displayName":"Work Mac"}"#,
            dataEncryptionKey: nil,
            lastMessage: nil
        )
        let localSession = APISession(
            id: "session-2",
            active: true,
            activeAt: 10,
            createdAt: 1,
            updatedAt: 15,
            metadataVersion: 1,
            metadata: #"{"name":"Standalone"}"#,
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
                cwd: "/tmp/remote",
                updatedAt: "2026-03-06T04:00:00.000Z",
                createdAt: "2026-03-06T03:00:00.000Z",
                archived: false
            )
        )

        let machineEntries = SessionListPresentationBuilder.machineEntries(
            sessions: [mirroredSession, localSession],
            upstreamSessions: [upstreamRow]
        )
        let localSessions = SessionListPresentationBuilder.localSessions(from: [mirroredSession, localSession])

        #expect(machineEntries.count == 2)
        #expect(localSessions.map(\.id) == ["session-2"])
        #expect(
            machineEntries.contains { entry in
                if case .mirroredSession(let session) = entry {
                    return session.id == "session-1"
                }
                return false
            }
        )
        #expect(
            machineEntries.contains { entry in
                if case .upstreamSession(let row) = entry {
                    return row.summary.id == "thread-2"
                }
                return false
            }
        )
    }

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
            upstreamSessions: [upstreamRow]
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
}
