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

    @Test
    func loadProjectsThrowsWhenAllMachineProjectFetchesFail() async {
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
            projectsByMachineID: [:],
            fetchProjectsError: MachinesAPIError.rpcCallFailed("Machine data encryption key is unavailable")
        )
        let useCase = SessionProjectsLoadUseCase(service: service)

        await #expect(throws: MachinesAPIError.rpcCallFailed("Machine data encryption key is unavailable")) {
            _ = try await useCase.loadProjects(
                serverURLString: "https://api.unhappy.im",
                token: "token"
            )
        }
    }

    @Test
    func loadProjectsTimesOutPerMachineWithoutBlockingSuccessfulMachines() async throws {
        let service = MockProjectsService(
            machines: [
                APIMachine(
                    id: "machine-fast",
                    active: true,
                    activeAt: 20,
                    createdAt: 1,
                    updatedAt: 20,
                    metadataVersion: 1,
                    metadata: #"{"displayName":"Fast Mac"}"#,
                    daemonStateVersion: 1,
                    daemonState: nil,
                    dataEncryptionKey: nil
                ),
                APIMachine(
                    id: "machine-slow",
                    active: true,
                    activeAt: 10,
                    createdAt: 1,
                    updatedAt: 10,
                    metadataVersion: 1,
                    metadata: #"{"displayName":"Slow Mac"}"#,
                    daemonStateVersion: 1,
                    daemonState: nil,
                    dataEncryptionKey: nil
                ),
            ],
            projectsByMachineID: [
                "machine-fast": [
                    APIMachineProjectSummary(
                        path: "/repo/app",
                        latestUpdatedAt: "2026-03-06T04:00:00.000Z",
                        codexThreadCount: 1,
                        claudeSessionCount: 0,
                        openedExplicitly: true
                    )
                ]
            ],
            delayedMachineIDs: ["machine-slow"],
            fetchDelay: .milliseconds(200)
        )
        let useCase = SessionProjectsLoadUseCase(
            service: service,
            machineRequestTimeout: .milliseconds(30)
        )

        let projects = try await useCase.loadProjects(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(projects.count == 1)
        #expect(projects.first?.machineID == "machine-fast")
    }

    @Test
    func loadProjectsStreamYieldsFastMachineBeforeSlowMachineTimesOut() async throws {
        let service = MockProjectsService(
            machines: [
                APIMachine(
                    id: "machine-fast",
                    active: true,
                    activeAt: 20,
                    createdAt: 1,
                    updatedAt: 20,
                    metadataVersion: 1,
                    metadata: #"{"displayName":"Fast Mac"}"#,
                    daemonStateVersion: 1,
                    daemonState: nil,
                    dataEncryptionKey: nil
                ),
                APIMachine(
                    id: "machine-slow",
                    active: true,
                    activeAt: 10,
                    createdAt: 1,
                    updatedAt: 10,
                    metadataVersion: 1,
                    metadata: #"{"displayName":"Slow Mac"}"#,
                    daemonStateVersion: 1,
                    daemonState: nil,
                    dataEncryptionKey: nil
                ),
            ],
            projectsByMachineID: [
                "machine-fast": [
                    APIMachineProjectSummary(
                        path: "/repo/app",
                        latestUpdatedAt: "2026-03-06T04:00:00.000Z",
                        codexThreadCount: 1,
                        claudeSessionCount: 0,
                        openedExplicitly: true
                    )
                ]
            ],
            delayedMachineIDs: ["machine-slow"],
            fetchDelay: .milliseconds(200)
        )
        let useCase = SessionProjectsLoadUseCase(
            service: service,
            machineRequestTimeout: .milliseconds(30)
        )
        var iterator = await useCase.loadProjectsStream(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        ).makeAsyncIterator()

        let firstSnapshot = await iterator.next()
        let finalSnapshot = await iterator.next()

        #expect(firstSnapshot?.isFinal == false)
        #expect(firstSnapshot?.machineID == "machine-fast")
        #expect(firstSnapshot?.projects.count == 1)
        #expect(firstSnapshot?.projects.first?.machineID == "machine-fast")
        #expect(finalSnapshot?.isFinal == true)
        #expect(finalSnapshot?.machineID == nil)
        #expect(finalSnapshot?.projects.isEmpty == true)
    }

    @Test
    func loadProjectsStreamYieldsEmptyMachineSnapshotWhenNoExplicitProjectsRemain() async throws {
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
                "machine-1": []
            ]
        )
        let useCase = SessionProjectsLoadUseCase(service: service)
        var iterator = await useCase.loadProjectsStream(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        ).makeAsyncIterator()

        let firstSnapshot = await iterator.next()
        let finalSnapshot = await iterator.next()

        #expect(firstSnapshot?.isFinal == false)
        #expect(firstSnapshot?.machineID == "machine-1")
        #expect(firstSnapshot?.projects.isEmpty == true)
        #expect(finalSnapshot?.isFinal == true)
    }

    @Test
    func loadProjectsIgnoresStaleActiveMachines() async throws {
        let now = Date.now.timeIntervalSince1970
        let service = MockProjectsService(
            machines: [
                APIMachine(
                    id: "machine-fresh",
                    active: true,
                    activeAt: now - 10,
                    createdAt: 1,
                    updatedAt: now - 10,
                    metadataVersion: 1,
                    metadata: #"{"displayName":"Fresh Mac"}"#,
                    daemonStateVersion: 1,
                    daemonState: nil,
                    dataEncryptionKey: nil
                ),
                APIMachine(
                    id: "machine-stale",
                    active: true,
                    activeAt: now - 120,
                    createdAt: 1,
                    updatedAt: now - 120,
                    metadataVersion: 1,
                    metadata: #"{"displayName":"Stale Mac"}"#,
                    daemonStateVersion: 1,
                    daemonState: nil,
                    dataEncryptionKey: nil
                ),
            ],
            projectsByMachineID: [
                "machine-fresh": [
                    APIMachineProjectSummary(
                        path: "/repo/fresh",
                        latestUpdatedAt: "2026-03-06T04:00:00.000Z",
                        codexThreadCount: 1,
                        claudeSessionCount: 0,
                        openedExplicitly: true
                    )
                ],
                "machine-stale": [
                    APIMachineProjectSummary(
                        path: "/repo/stale",
                        latestUpdatedAt: "2026-03-06T05:00:00.000Z",
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

        #expect(projects.map(\.machineID) == ["machine-fresh"])
        #expect(projects.map(\.summary.path) == ["/repo/fresh"])
    }
}

private actor MockProjectsService: MachinesFetching, MachineProjectsFetching {
    let machines: [APIMachine]
    let projectsByMachineID: [String: [APIMachineProjectSummary]]
    let fetchProjectsError: Error?
    let delayedMachineIDs: Set<String>
    let fetchDelay: Duration?
    private(set) var requestedExplicitOnlyValues: [Bool] = []

    init(
        machines: [APIMachine],
        projectsByMachineID: [String: [APIMachineProjectSummary]],
        fetchProjectsError: Error? = nil,
        delayedMachineIDs: Set<String> = [],
        fetchDelay: Duration? = nil
    ) {
        self.machines = machines
        self.projectsByMachineID = projectsByMachineID
        self.fetchProjectsError = fetchProjectsError
        self.delayedMachineIDs = delayedMachineIDs
        self.fetchDelay = fetchDelay
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
        if delayedMachineIDs.contains(machineID), let fetchDelay {
            try await Task.sleep(for: fetchDelay)
        }
        if let fetchProjectsError {
            throw fetchProjectsError
        }
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
