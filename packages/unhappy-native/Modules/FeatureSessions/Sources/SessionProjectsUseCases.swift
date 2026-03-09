import Foundation
import CoreKit
import FeatureNewSession

public protocol SessionProjectsLoadingAction: Sendable {
    func loadProjects(
        serverURLString: String,
        token: String
    ) async throws -> [SessionMachineProject]
}

public protocol SessionProjectOpeningAction: Sendable {
    func openProject(
        serverURLString: String,
        token: String,
        machineID: String,
        machineDisplayName: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> SessionMachineProject
}

public protocol SessionProjectRemovingAction: Sendable {
    func removeProject(
        serverURLString: String,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> SessionMachineProject
}

public actor SessionProjectsLoadUseCase: SessionProjectsLoadingAction {
    private let service: any MachinesFetching & MachineProjectsFetching

    public init(service: any MachinesFetching & MachineProjectsFetching) {
        self.service = service
    }

    public func loadProjects(
        serverURLString: String,
        token: String
    ) async throws -> [SessionMachineProject] {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else { return [] }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            return []
        }

        let machines = try await service.fetchMachines(serverURL: serverURL, token: normalizedToken)
        let activeMachines = machines.filter(\.active)
        var projects: [SessionMachineProject] = []
        let service = self.service

        try await withThrowingTaskGroup(of: [SessionMachineProject].self) { group in
            for machine in activeMachines {
                let machineDisplayName = machineName(for: machine)
                group.addTask {
                    do {
                        let machineProjects = try await service.fetchProjects(
                            serverURL: serverURL,
                            token: normalizedToken,
                            machineID: machine.id,
                            explicitOnly: true,
                            wrappedMachineDataEncryptionKey: machine.dataEncryptionKey
                        )
                        return machineProjects.map {
                            SessionMachineProject(
                                machineID: machine.id,
                                machineDisplayName: machineDisplayName,
                                wrappedMachineDataEncryptionKey: machine.dataEncryptionKey,
                                summary: $0
                            )
                        }
                    } catch {
                        return []
                    }
                }
            }

            for try await machineProjects in group {
                projects.append(contentsOf: machineProjects)
            }
        }

        return projects.sorted { lhs, rhs in
            let lhsDate = Date.parseISO8601(lhs.summary.latestUpdatedAt) ?? .distantPast
            let rhsDate = Date.parseISO8601(rhs.summary.latestUpdatedAt) ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            if lhs.machineDisplayName != rhs.machineDisplayName {
                return lhs.machineDisplayName.localizedCaseInsensitiveCompare(rhs.machineDisplayName) == .orderedAscending
            }
            return lhs.summary.path.localizedCaseInsensitiveCompare(rhs.summary.path) == .orderedAscending
        }
    }

    private func machineName(for machine: APIMachine) -> String {
        NewSessionMachinePresentation.displayName(for: machine)
    }
}

public actor SessionProjectOpenUseCase: SessionProjectOpeningAction {
    private let service: any MachineProjectOpening

    public init(service: any MachineProjectOpening) {
        self.service = service
    }

    public func openProject(
        serverURLString: String,
        token: String,
        machineID: String,
        machineDisplayName: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> SessionMachineProject {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw MachinesAPIError.missingToken
        }
        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let serverURL = URL(string: normalizedURL),
              serverURL.scheme != nil,
              serverURL.host != nil else {
            throw MachinesAPIError.invalidHTTPStatus(0)
        }
        let result = try await service.openProject(
            serverURL: serverURL,
            token: normalizedToken,
            machineID: machineID,
            path: path,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey
        )
        if result.success == false {
            throw MachinesAPIError.rpcCallFailed(result.error ?? result.message)
        }
        return SessionMachineProject(
            machineID: machineID,
            machineDisplayName: machineDisplayName,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            summary: APIMachineProjectSummary(
                path: path,
                latestUpdatedAt: Date().ISO8601Format(),
                codexThreadCount: 0,
                claudeSessionCount: 0,
                openedExplicitly: true
            )
        )
    }
}

public actor SessionProjectRemoveUseCase: SessionProjectRemovingAction {
    private let service: any MachineProjectRemoving

    public init(service: any MachineProjectRemoving) {
        self.service = service
    }

    public func removeProject(
        serverURLString: String,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> SessionMachineProject {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw MachinesAPIError.missingToken
        }
        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let serverURL = URL(string: normalizedURL),
              serverURL.scheme != nil,
              serverURL.host != nil else {
            throw MachinesAPIError.invalidHTTPStatus(0)
        }
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw MachinesAPIError.missingPath
        }
        let result = try await service.removeProject(
            serverURL: serverURL,
            token: normalizedToken,
            machineID: machineID,
            path: normalizedPath,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey
        )
        if result.success == false {
            throw MachinesAPIError.rpcCallFailed(result.error ?? result.message)
        }
        return SessionMachineProject(
            machineID: machineID,
            machineDisplayName: machineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            summary: APIMachineProjectSummary(
                path: normalizedPath,
                latestUpdatedAt: Date().ISO8601Format(),
                codexThreadCount: 0,
                claudeSessionCount: 0,
                openedExplicitly: false
            )
        )
    }
}

private extension Date {
    static func parseISO8601(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        return fallbackFormatter.date(from: value)
    }
}
