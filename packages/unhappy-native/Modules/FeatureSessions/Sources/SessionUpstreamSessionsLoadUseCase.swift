import Foundation
import CoreKit

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
            let lhsDate = timestamp(from: lhs.summary.updatedAt ?? lhs.summary.createdAt)
            let rhsDate = timestamp(from: rhs.summary.updatedAt ?? rhs.summary.createdAt)
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            if lhs.machineDisplayName != rhs.machineDisplayName {
                return lhs.machineDisplayName.localizedCaseInsensitiveCompare(rhs.machineDisplayName) == .orderedAscending
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
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

    private func timestamp(from value: String?) -> TimeInterval {
        guard let value else { return 0 }
        if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: value) {
            return date.timeIntervalSince1970
        }
        if let date = ISO8601DateFormatter.withInternetDateTime.date(from: value) {
            return date.timeIntervalSince1970
        }
        return 0
    }
}

private extension ISO8601DateFormatter {
    nonisolated(unsafe) static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) static let withInternetDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
