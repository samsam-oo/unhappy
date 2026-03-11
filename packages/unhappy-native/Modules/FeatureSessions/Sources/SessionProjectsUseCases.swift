import Foundation
import CoreKit
import SessionKit

public protocol SessionProjectsLoadingAction: Sendable {
    func loadProjects(
        serverURLString: String,
        token: String
    ) async throws -> [SessionMachineProject]
}

public struct SessionProjectsLoadSnapshot: Sendable, Equatable {
    public let machineID: String?
    public let projects: [SessionMachineProject]
    public let errorMessage: String?
    public let isFinal: Bool

    public init(
        machineID: String?,
        projects: [SessionMachineProject],
        errorMessage: String?,
        isFinal: Bool
    ) {
        self.machineID = machineID
        self.projects = projects
        self.errorMessage = errorMessage
        self.isFinal = isFinal
    }
}

public protocol SessionProjectsStreamingAction: Sendable {
    func loadProjectsStream(
        serverURLString: String,
        token: String
    ) async -> AsyncStream<SessionProjectsLoadSnapshot>
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

public actor SessionProjectsLoadUseCase: SessionProjectsLoadingAction, SessionProjectsStreamingAction {
    private struct MachineProjectsBatch: Sendable {
        let machineID: String
        let projects: [SessionMachineProject]
        let error: Error?
    }

    private let service: any MachinesFetching & MachineProjectsFetching
    private let machineRequestTimeout: Duration

    public init(
        service: any MachinesFetching & MachineProjectsFetching,
        machineRequestTimeout: Duration? = nil
    ) {
        self.service = service
        self.machineRequestTimeout = machineRequestTimeout ?? SessionLoadTimeout.projects
    }

    public func loadProjects(
        serverURLString: String,
        token: String
    ) async throws -> [SessionMachineProject] {
        var finalSnapshot = SessionProjectsLoadSnapshot(
            machineID: nil,
            projects: [],
            errorMessage: nil,
            isFinal: true
        )
        var aggregatedProjects: [SessionMachineProject] = []
        for await snapshot in await loadProjectsStream(
            serverURLString: serverURLString,
            token: token
        ) {
            finalSnapshot = snapshot
            if let machineID = snapshot.machineID {
                aggregatedProjects = mergeMachineScopedProjects(
                    existing: aggregatedProjects,
                    refreshed: snapshot.projects,
                    machineID: machineID
                )
            }
        }

        if aggregatedProjects.isEmpty,
           let errorMessage = finalSnapshot.errorMessage,
           !errorMessage.isEmpty {
            throw MachinesAPIError.rpcCallFailed(errorMessage)
        }

        return aggregatedProjects
    }

    public func loadProjectsStream(
        serverURLString: String,
        token: String
    ) async -> AsyncStream<SessionProjectsLoadSnapshot> {
        AsyncStream { continuation in
            let task = Task {
                await self.streamProjects(
                    serverURLString: serverURLString,
                    token: token,
                    continuation: continuation
                )
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func streamProjects(
        serverURLString: String,
        token: String,
        continuation: AsyncStream<SessionProjectsLoadSnapshot>.Continuation
    ) async {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            continuation.yield(
                SessionProjectsLoadSnapshot(machineID: nil, projects: [], errorMessage: nil, isFinal: true)
            )
            continuation.finish()
            return
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            continuation.yield(
                SessionProjectsLoadSnapshot(machineID: nil, projects: [], errorMessage: nil, isFinal: true)
            )
            continuation.finish()
            return
        }

        do {
            let machines = try await service.fetchMachines(serverURL: serverURL, token: normalizedToken)
            guard !Task.isCancelled else {
                continuation.finish()
                return
            }
            let activeMachines = SessionMachineActivityGuard.eligibleMachines(from: machines)
            var projects: [SessionMachineProject] = []
            var firstError: Error?
            let service = self.service
            let machineRequestTimeout = self.machineRequestTimeout

            await withTaskGroup(of: MachineProjectsBatch.self) { group in
                for machine in activeMachines {
                    let machineDisplayName = machineName(for: machine)
                    group.addTask {
                        do {
                            let machineProjects = try await withSessionLoadTimeout(machineRequestTimeout) {
                                try await service.fetchProjects(
                                    serverURL: serverURL,
                                    token: normalizedToken,
                                    machineID: machine.id,
                                    explicitOnly: true,
                                    wrappedMachineDataEncryptionKey: machine.dataEncryptionKey
                                )
                            }
                            return MachineProjectsBatch(
                                machineID: machine.id,
                                projects: machineProjects.map {
                                    SessionMachineProject(
                                        machineID: machine.id,
                                        machineDisplayName: machineDisplayName,
                                        wrappedMachineDataEncryptionKey: machine.dataEncryptionKey,
                                        summary: $0
                                    )
                                },
                                error: nil
                            )
                        } catch {
                            return MachineProjectsBatch(
                                machineID: machine.id,
                                projects: [],
                                error: error
                            )
                        }
                    }
                }

                for await batch in group {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    projects.append(contentsOf: batch.projects)
                    projects = sortedProjects(projects)
                    if batch.error == nil {
                        continuation.yield(
                            SessionProjectsLoadSnapshot(
                                machineID: batch.machineID,
                                projects: batch.projects,
                                errorMessage: nil,
                                isFinal: false
                            )
                        )
                    }
                    if firstError == nil {
                        firstError = batch.error
                    }
                }
            }

            let finalErrorMessage: String?
            if projects.isEmpty, let firstError {
                if let machinesError = firstError as? MachinesAPIError {
                    finalErrorMessage = machinesError.errorDescription
                } else {
                    let message = (firstError as? LocalizedError)?.errorDescription ?? firstError.localizedDescription
                    let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
                    finalErrorMessage = normalizedMessage.isEmpty ? nil : normalizedMessage
                }
            } else {
                finalErrorMessage = nil
            }

            continuation.yield(
                SessionProjectsLoadSnapshot(
                    machineID: nil,
                    projects: [],
                    errorMessage: finalErrorMessage,
                    isFinal: true
                )
            )
            continuation.finish()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            continuation.yield(
                SessionProjectsLoadSnapshot(
                    machineID: nil,
                    projects: [],
                    errorMessage: message.trimmingCharacters(in: .whitespacesAndNewlines),
                    isFinal: true
                )
            )
            continuation.finish()
        }
    }

    private func machineName(for machine: APIMachine) -> String {
        NewSessionMachinePresentation.displayName(for: machine)
    }

    private func sortedProjects(
        _ projects: [SessionMachineProject]
    ) -> [SessionMachineProject] {
        projects.sorted { lhs, rhs in
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

    private func mergeMachineScopedProjects(
        existing: [SessionMachineProject],
        refreshed: [SessionMachineProject],
        machineID: String
    ) -> [SessionMachineProject] {
        let retained = existing.filter { $0.machineID != machineID }
        return sortedProjects(retained + refreshed)
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

extension Date {
    private static func fractionalISO8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func internetISO8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    static func parseISO8601(_ value: String) -> Date? {
        if let date = fractionalISO8601Formatter().date(from: value) {
            return date
        }
        return internetISO8601Formatter().date(from: value)
    }
}
