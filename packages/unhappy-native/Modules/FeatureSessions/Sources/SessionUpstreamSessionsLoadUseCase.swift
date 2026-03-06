import Foundation
import CoreKit

public protocol SessionUpstreamSessionsLoadingAction: Sendable {
    func loadUpstreamSessions(
        serverURLString: String,
        token: String
    ) async throws -> [SessionLinkedUpstreamSession]
}

public actor SessionUpstreamSessionsLoadUseCase: SessionUpstreamSessionsLoadingAction {
    private let service: any MachinesFetching & MachineCodexThreadsFetching & MachineClaudeSessionsFetching

    public init(service: any MachinesFetching & MachineCodexThreadsFetching & MachineClaudeSessionsFetching) {
        self.service = service
    }

    public func loadUpstreamSessions(
        serverURLString: String,
        token: String
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
        var rows: [SessionLinkedUpstreamSession] = []

        for machine in activeMachines {
            let machineDisplayName = machineName(for: machine)
            async let codexRows = loadCodexRows(
                machine: machine,
                machineDisplayName: machineDisplayName,
                serverURL: serverURL,
                token: normalizedToken
            )
            async let claudeRows = loadClaudeRows(
                machine: machine,
                machineDisplayName: machineDisplayName,
                serverURL: serverURL,
                token: normalizedToken
            )
            rows.append(contentsOf: try await codexRows)
            rows.append(contentsOf: try await claudeRows)
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

    private func loadCodexRows(
        machine: APIMachine,
        machineDisplayName: String,
        serverURL: URL,
        token: String
    ) async throws -> [SessionLinkedUpstreamSession] {
        let threads = try await service.fetchCodexThreads(
            serverURL: serverURL,
            token: token,
            machineID: machine.id,
            limit: 50,
            cwd: nil
        )
        return threads.map {
            SessionLinkedUpstreamSession(
                machineID: machine.id,
                machineDisplayName: machineDisplayName,
                summary: $0.upstreamSummary
            )
        }
    }

    private func loadClaudeRows(
        machine: APIMachine,
        machineDisplayName: String,
        serverURL: URL,
        token: String
    ) async throws -> [SessionLinkedUpstreamSession] {
        let sessions = try await service.fetchClaudeSessions(
            serverURL: serverURL,
            token: token,
            machineID: machine.id,
            limit: 50,
            cwd: nil
        )
        return sessions.map {
            SessionLinkedUpstreamSession(
                machineID: machine.id,
                machineDisplayName: machineDisplayName,
                summary: $0.upstreamSummary
            )
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

    private func timestamp(from value: String?) -> TimeInterval {
        guard let value else { return 0 }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date.timeIntervalSince1970
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date.timeIntervalSince1970
        }
        return 0
    }
}
