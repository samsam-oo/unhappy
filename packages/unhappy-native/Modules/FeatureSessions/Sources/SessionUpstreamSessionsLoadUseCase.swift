import Foundation
import CoreKit
import SessionKit

public protocol SessionUpstreamSessionsLoadingAction: Sendable {
    func loadUpstreamSessions(
        serverURLString: String,
        token: String,
        projects: [SessionMachineProject]
    ) async throws -> [SessionLinkedUpstreamSession]
}

public struct SessionUpstreamSessionsLoadSnapshot: Sendable, Equatable {
    public let machineID: String?
    public let projectPath: String?
    public let rows: [SessionLinkedUpstreamSession]
    public let errorMessage: String?
    public let isFinal: Bool

    public init(
        machineID: String?,
        projectPath: String?,
        rows: [SessionLinkedUpstreamSession],
        errorMessage: String?,
        isFinal: Bool
    ) {
        self.machineID = machineID
        self.projectPath = projectPath
        self.rows = rows
        self.errorMessage = errorMessage
        self.isFinal = isFinal
    }
}

public protocol SessionUpstreamSessionsStreamingAction: Sendable {
    func loadUpstreamSessionsStream(
        serverURLString: String,
        token: String,
        projects: [SessionMachineProject]
    ) async -> AsyncStream<SessionUpstreamSessionsLoadSnapshot>
}

public actor SessionUpstreamSessionsLoadUseCase: SessionUpstreamSessionsLoadingAction, SessionUpstreamSessionsStreamingAction {
    private let service: any MachinesFetching & MachineCodexThreadsFetching & MachineClaudeSessionsFetching & MachineGeminiSessionsFetching
    private let upstreamRequestTimeout: Duration

    public init(
        service: any MachinesFetching & MachineCodexThreadsFetching & MachineClaudeSessionsFetching & MachineGeminiSessionsFetching,
        upstreamRequestTimeout: Duration? = nil
    ) {
        self.service = service
        self.upstreamRequestTimeout = upstreamRequestTimeout ?? SessionLoadTimeout.upstreamSessions
    }

    public func loadUpstreamSessions(
        serverURLString: String,
        token: String,
        projects: [SessionMachineProject]
    ) async throws -> [SessionLinkedUpstreamSession] {
        var finalSnapshot = SessionUpstreamSessionsLoadSnapshot(
            machineID: nil,
            projectPath: nil,
            rows: [],
            errorMessage: nil,
            isFinal: true
        )
        var aggregatedRows: [SessionLinkedUpstreamSession] = []
        for await snapshot in await loadUpstreamSessionsStream(
            serverURLString: serverURLString,
            token: token,
            projects: projects
        ) {
            finalSnapshot = snapshot
            if let machineID = snapshot.machineID,
               let projectPath = snapshot.projectPath {
                aggregatedRows = mergeProjectScopedRows(
                    existing: aggregatedRows,
                    refreshed: snapshot.rows,
                    machineID: machineID,
                    projectPath: projectPath
                )
            }
        }

        if aggregatedRows.isEmpty,
           let errorMessage = finalSnapshot.errorMessage,
           !errorMessage.isEmpty {
            throw MachinesAPIError.rpcCallFailed(errorMessage)
        }

        return aggregatedRows
    }

    public func loadUpstreamSessionsStream(
        serverURLString: String,
        token: String,
        projects: [SessionMachineProject]
    ) async -> AsyncStream<SessionUpstreamSessionsLoadSnapshot> {
        AsyncStream { continuation in
            let task = Task {
                await self.streamUpstreamSessions(
                    serverURLString: serverURLString,
                    token: token,
                    projects: projects,
                    continuation: continuation
                )
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func streamUpstreamSessions(
        serverURLString: String,
        token: String,
        projects: [SessionMachineProject],
        continuation: AsyncStream<SessionUpstreamSessionsLoadSnapshot>.Continuation
    ) async {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            continuation.yield(.init(machineID: nil, projectPath: nil, rows: [], errorMessage: nil, isFinal: true))
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
            continuation.yield(.init(machineID: nil, projectPath: nil, rows: [], errorMessage: nil, isFinal: true))
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
            let projectPathsByMachineID = groupedProjectPathsByMachineID(from: projects)
            var rows: [SessionLinkedUpstreamSession] = []
            var seenRowIDs = Set<String>()
            var firstErrorMessage: String?
            let service = self.service
            let upstreamRequestTimeout = self.upstreamRequestTimeout

            await withTaskGroup(of: SessionUpstreamSessionsLoadSnapshot.self) { group in
                for machine in activeMachines {
                    let machineProjects = projectPathsByMachineID[machine.id] ?? []
                    guard !machineProjects.isEmpty else { continue }

                    let machineDisplayName = machineName(for: machine)
                    for projectPath in machineProjects {
                        group.addTask {
                            do {
                                let batch = try await withSessionLoadTimeout(upstreamRequestTimeout) {
                                    async let codexThreads = service.fetchCodexThreads(
                                        serverURL: serverURL,
                                        token: normalizedToken,
                                        machineID: machine.id,
                                        wrappedMachineDataEncryptionKey: machine.dataEncryptionKey,
                                        limit: 50,
                                        cwd: projectPath
                                    )
                                    async let claudeSessions = service.fetchClaudeSessions(
                                        serverURL: serverURL,
                                        token: normalizedToken,
                                        machineID: machine.id,
                                        wrappedMachineDataEncryptionKey: machine.dataEncryptionKey,
                                        limit: 50,
                                        cwd: projectPath
                                    )
                                    async let geminiSessions = service.fetchGeminiSessions(
                                        serverURL: serverURL,
                                        token: normalizedToken,
                                        machineID: machine.id,
                                        wrappedMachineDataEncryptionKey: machine.dataEncryptionKey,
                                        limit: 50,
                                        cwd: projectPath
                                    )
                                    let (threads, sessions, geminiRows) = try await (codexThreads, claudeSessions, geminiSessions)
                                    return threads.map {
                                        SessionLinkedUpstreamSession(
                                            machineID: machine.id,
                                            machineDisplayName: machineDisplayName,
                                            wrappedMachineDataEncryptionKey: machine.dataEncryptionKey,
                                            summary: $0.upstreamSummary
                                        )
                                    } + sessions.map {
                                        SessionLinkedUpstreamSession(
                                            machineID: machine.id,
                                            machineDisplayName: machineDisplayName,
                                            wrappedMachineDataEncryptionKey: machine.dataEncryptionKey,
                                            summary: $0.upstreamSummary
                                        )
                                    } + geminiRows.map {
                                        SessionLinkedUpstreamSession(
                                            machineID: machine.id,
                                            machineDisplayName: machineDisplayName,
                                            wrappedMachineDataEncryptionKey: machine.dataEncryptionKey,
                                            summary: $0.upstreamSummary
                                        )
                                    }
                                }
                                return SessionUpstreamSessionsLoadSnapshot(
                                    machineID: machine.id,
                                    projectPath: projectPath,
                                    rows: batch,
                                    errorMessage: nil,
                                    isFinal: false
                                )
                            } catch {
                                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                                let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
                                return SessionUpstreamSessionsLoadSnapshot(
                                    machineID: machine.id,
                                    projectPath: projectPath,
                                    rows: [],
                                    errorMessage: normalizedMessage.isEmpty ? nil : normalizedMessage,
                                    isFinal: false
                                )
                            }
                        }
                    }
                }

                for await snapshot in group {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    for row in snapshot.rows where seenRowIDs.insert(row.id).inserted {
                        rows.append(row)
                    }
                    rows = sortedRows(rows)
                    if snapshot.rows.isEmpty == false {
                        continuation.yield(
                            SessionUpstreamSessionsLoadSnapshot(
                                machineID: snapshot.machineID,
                                projectPath: snapshot.projectPath,
                                rows: snapshot.rows,
                                errorMessage: nil,
                                isFinal: false
                            )
                        )
                    }
                    if firstErrorMessage == nil,
                       let errorMessage = snapshot.errorMessage,
                       !errorMessage.isEmpty {
                        firstErrorMessage = errorMessage
                    }
                }
            }

            continuation.yield(
                SessionUpstreamSessionsLoadSnapshot(
                    machineID: nil,
                    projectPath: nil,
                    rows: [],
                    errorMessage: rows.isEmpty ? firstErrorMessage : nil,
                    isFinal: true
                )
            )
            continuation.finish()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            continuation.yield(
                SessionUpstreamSessionsLoadSnapshot(
                    machineID: nil,
                    projectPath: nil,
                    rows: [],
                    errorMessage: normalizedMessage.isEmpty ? nil : normalizedMessage,
                    isFinal: true
                )
            )
            continuation.finish()
        }
    }

    private func machineName(for machine: APIMachine) -> String {
        NewSessionMachinePresentation.displayName(for: machine)
    }

    private func groupedProjectPathsByMachineID(
        from projects: [SessionMachineProject]
    ) -> [String: [String]] {
        var grouped: [String: Set<String>] = [:]
        for project in projects {
            guard let path = SessionProjectPathCanonicalizer.canonicalPath(project.summary.path) else {
                continue
            }
            grouped[project.machineID, default: []].insert(path)
        }
        return grouped.mapValues { Array($0).sorted() }
    }

    private func sortedRows(
        _ rows: [SessionLinkedUpstreamSession]
    ) -> [SessionLinkedUpstreamSession] {
        rows.sorted { lhs, rhs in
            if lhs.sortTimestamp != rhs.sortTimestamp {
                return lhs.sortTimestamp > rhs.sortTimestamp
            }
            if lhs.machineDisplayName != rhs.machineDisplayName {
                return lhs.machineDisplayName.localizedCaseInsensitiveCompare(rhs.machineDisplayName) == .orderedAscending
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func mergeProjectScopedRows(
        existing: [SessionLinkedUpstreamSession],
        refreshed: [SessionLinkedUpstreamSession],
        machineID: String,
        projectPath: String
    ) -> [SessionLinkedUpstreamSession] {
        let targetProjectID = canonicalProjectID(
            machineID: machineID,
            projectPath: projectPath
        )
        let retained = existing.filter { row in
            canonicalProjectID(
                machineID: row.machineID,
                projectPath: row.summary.cwd ?? ""
            ) != targetProjectID
        }
        return sortedRows(retained + refreshed)
    }

    private func canonicalProjectID(
        machineID: String,
        projectPath: String
    ) -> String? {
        guard let normalizedPath = SessionProjectPathCanonicalizer.canonicalPath(projectPath) else {
            return nil
        }
        return "\(machineID)|\(normalizedPath)"
    }
}
