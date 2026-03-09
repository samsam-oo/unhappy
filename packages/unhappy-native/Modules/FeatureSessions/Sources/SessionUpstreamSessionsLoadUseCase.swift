import Foundation
import CoreKit
import FeatureNewSession

public protocol SessionUpstreamSessionsLoadingAction: Sendable {
    func loadUpstreamSessions(
        serverURLString: String,
        token: String,
        projects: [SessionMachineProject]
    ) async throws -> [SessionLinkedUpstreamSession]
}

public actor SessionUpstreamSessionsLoadUseCase: SessionUpstreamSessionsLoadingAction {
    private let service: any MachinesFetching & MachineCodexThreadsFetching & MachineClaudeSessionsFetching & MachineGeminiSessionsFetching

    public init(service: any MachinesFetching & MachineCodexThreadsFetching & MachineClaudeSessionsFetching & MachineGeminiSessionsFetching) {
        self.service = service
    }

    public func loadUpstreamSessions(
        serverURLString: String,
        token: String,
        projects: [SessionMachineProject]
    ) async throws -> [SessionLinkedUpstreamSession] {
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
        let projectPathsByMachineID = groupedProjectPathsByMachineID(from: projects)
        var rows: [SessionLinkedUpstreamSession] = []
        var seenRowIDs = Set<String>()
        let service = self.service

        try await withThrowingTaskGroup(of: [SessionLinkedUpstreamSession].self) { group in
            for machine in activeMachines {
                let machineProjects = projectPathsByMachineID[machine.id] ?? []
                guard !machineProjects.isEmpty else { continue }

                let machineDisplayName = machineName(for: machine)
                for projectPath in machineProjects {
                    group.addTask {
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
                }
            }

            for try await batch in group {
                for row in batch where seenRowIDs.insert(row.id).inserted {
                    rows.append(row)
                }
            }
        }

        return rows.sorted { lhs, rhs in
            if lhs.sortTimestamp != rhs.sortTimestamp {
                return lhs.sortTimestamp > rhs.sortTimestamp
            }
            if lhs.machineDisplayName != rhs.machineDisplayName {
                return lhs.machineDisplayName.localizedCaseInsensitiveCompare(rhs.machineDisplayName) == .orderedAscending
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
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

}
