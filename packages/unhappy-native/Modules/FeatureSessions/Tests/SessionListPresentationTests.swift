import Testing
@testable import FeatureSessions
import CoreKit
import SessionKit

struct SessionListPresentationTests {
    @Test
    func projectGroupsClusterSessionsByMachineAndProjectPath() {
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
        #expect(groups.first?.upstreamSessions.map(\.summary.id) == ["thread-2"])
        #expect(groups.first?.allSessionCount == 3)
    }

    @Test
    func projectGroupsIncludeBookmarkedProjectWithoutExistingSessions() {
        let groups = SessionListPresentationBuilder.projectGroups(
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
        let upstreamRow = SessionLinkedUpstreamSession(
            machineID: "machine-1",
            machineDisplayName: "Work Mac",
            summary: APIUpstreamSessionSummary(
                id: "thread-3",
                provider: .codex,
                title: "Direct Only",
                cwd: "/repo/runtime",
                updatedAt: "2026-03-06T06:00:00.000Z",
                createdAt: "2026-03-06T05:00:00.000Z",
                archived: false
            )
        )

        let groups = SessionListPresentationBuilder.projectGroups(
            upstreamSessions: [upstreamRow],
            projects: []
        )

        #expect(groups.count == 1)
        #expect(groups.first?.projectPath == "/repo/runtime")
        #expect(groups.first?.projectDisplayPath == "/repo/runtime")
        #expect(groups.first?.hasConcreteProjectPath == true)
        #expect(groups.first?.upstreamSessions.map(\.summary.id) == ["thread-3"])
        #expect(groups.first?.allSessionCount == 1)
    }

    @Test
    func projectGroupsMatchHomeRelativeSessionPathToAbsoluteProject() {
        let groups = SessionListPresentationBuilder.projectGroups(
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
        #expect(groups.first?.upstreamSessions.isEmpty == true)
        #expect(groups.first?.allSessionCount == 1)
    }

    @Test
    func projectGroupsPreferServerProvidedDisplayPathVerbatim() {
        let groups = SessionListPresentationBuilder.projectGroups(
            upstreamSessions: [],
            projects: [
                SessionMachineProject(
                    machineID: "machine-1",
                    machineDisplayName: "Phone",
                    summary: APIMachineProjectSummary(
                        path: "~/Downloads/shadow-client",
                        displayPath: "~/Downloads/shadow-client",
                        latestUpdatedAt: "2026-03-06T00:00:00.000Z",
                        codexThreadCount: 0,
                        claudeSessionCount: 0,
                        openedExplicitly: true
                    )
                )
            ]
        )

        #expect(groups.first?.projectPath == "~/Downloads/shadow-client")
        #expect(groups.first?.projectDisplayPath == "~/Downloads/shadow-client")
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
            upstreamSessions: [upstreamRow],
            projects: [project]
        )

        #expect(resolvedGroup?.upstreamSessions.map(\.summary.id) == ["thread-1"])
    }

    @Test
    func projectGroupsCollapseMirroredDuplicatesAndMatchingUpstreamRows() {
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
        #expect(groups.first?.displayUpstreamSessions.map(\.summary.id) == ["thread-1"])
        #expect(groups.first?.allSessionCount == 1)
    }
}
