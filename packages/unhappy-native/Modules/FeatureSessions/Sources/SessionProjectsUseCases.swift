import Foundation
import CoreKit

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
        path: String
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

        for machine in activeMachines {
            let machineDisplayName = machineName(for: machine)
            let machineProjects = try await service.fetchProjects(
                serverURL: serverURL,
                token: normalizedToken,
                machineID: machine.id
            )
            projects.append(
                contentsOf: machineProjects.map {
                    SessionMachineProject(
                        machineID: machine.id,
                        machineDisplayName: machineDisplayName,
                        summary: $0
                    )
                }
            )
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
        let payload = machine.metadata.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return machine.id
        }
        let keys = ["displayName", "name", "host", "hostname"]
        for key in keys {
            if let value = object[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return machine.id
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
        path: String
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
            path: path
        )
        if result.success == false {
            throw MachinesAPIError.rpcCallFailed(result.error ?? result.message)
        }
        return SessionMachineProject(
            machineID: machineID,
            machineDisplayName: machineDisplayName,
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

private extension Date {
    static func parseISO8601(_ value: String) -> Date? {
        ISO8601DateFormatter.withFractional.date(from: value)
            ?? ISO8601DateFormatter.withInternet.date(from: value)
    }
}

private extension ISO8601DateFormatter {
    static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let withInternet: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
