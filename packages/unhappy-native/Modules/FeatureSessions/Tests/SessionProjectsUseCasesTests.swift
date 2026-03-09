import Foundation
import Testing
@testable import FeatureSessions
import CoreKit

struct SessionProjectsUseCasesTests {
    @Test
    func loadProjectsExpandsMachineProjectsAcrossActiveMachines() async throws {
        let service = MockProjectsService(
            machines: [
                APIMachine(
                    id: "machine-1",
                    active: true,
                    activeAt: 10,
                    createdAt: 1,
                    updatedAt: 10,
                    metadataVersion: 1,
                    metadata: #"{"displayName":"Work Mac"}"#,
                    daemonStateVersion: 1,
                    daemonState: nil,
                    dataEncryptionKey: nil
                )
            ],
            projectsByMachineID: [
                "machine-1": [
                    APIMachineProjectSummary(
                        path: "/repo/app",
                        latestUpdatedAt: "2026-03-06T04:00:00.000Z",
                        codexThreadCount: 1,
                        claudeSessionCount: 0,
                        openedExplicitly: true
                    )
                ]
            ]
        )
        let useCase = SessionProjectsLoadUseCase(service: service)

        let projects = try await useCase.loadProjects(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(projects.count == 1)
        #expect(projects.first?.machineID == "machine-1")
        #expect(projects.first?.machineDisplayName == "Work Mac")
        #expect(projects.first?.summary.path == "/repo/app")
        let explicitFlags = await service.requestedExplicitOnlyValues
        #expect(explicitFlags == [true])
    }

    @Test
    func openProjectReturnsOpenedProjectSummary() async throws {
        let service = MockProjectOpener()
        let useCase = SessionProjectOpenUseCase(service: service)

        let project = try await useCase.openProject(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            machineID: "machine-1",
            machineDisplayName: "Work Mac",
            path: "/repo/app",
            wrappedMachineDataEncryptionKey: nil
        )

        #expect(project.machineID == "machine-1")
        #expect(project.machineDisplayName == "Work Mac")
        #expect(project.summary.path == "/repo/app")
        #expect(project.summary.openedExplicitly == true)
    }
}

private actor MockProjectsService: MachinesFetching, MachineProjectsFetching {
    let machines: [APIMachine]
    let projectsByMachineID: [String: [APIMachineProjectSummary]]
    private(set) var requestedExplicitOnlyValues: [Bool] = []

    init(
        machines: [APIMachine],
        projectsByMachineID: [String: [APIMachineProjectSummary]]
    ) {
        self.machines = machines
        self.projectsByMachineID = projectsByMachineID
    }

    func fetchMachines(serverURL: URL, token: String) async throws -> [APIMachine] {
        machines
    }

    func fetchProjects(
        serverURL: URL,
        token: String,
        machineID: String,
        explicitOnly: Bool,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> [APIMachineProjectSummary] {
        requestedExplicitOnlyValues.append(explicitOnly)
        return projectsByMachineID[machineID] ?? []
    }
}

private actor MockProjectOpener: MachineProjectOpening {
    func openProject(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APIMachineCommandResult {
        APIMachineCommandResult(
            success: true,
            message: "opened",
            error: nil
        )
    }
}
