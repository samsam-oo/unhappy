import Foundation
import CoreKit

public enum SessionListPresentationBuilder {}

public struct SessionProjectGroup: Identifiable, Equatable, Sendable {
    public let machineID: String
    public let machineDisplayName: String
    public let wrappedMachineDataEncryptionKey: String?
    public let projectPath: String
    public let projectDisplayPath: String
    public let hasConcreteProjectPath: Bool
    public let catalogSessionCount: Int
    public let catalogLatestUpdatedAt: TimeInterval
    public let upstreamSessions: [SessionLinkedUpstreamSession]

    public init(
        machineID: String,
        machineDisplayName: String,
        wrappedMachineDataEncryptionKey: String? = nil,
        projectPath: String,
        projectDisplayPath: String? = nil,
        hasConcreteProjectPath: Bool,
        catalogSessionCount: Int = 0,
        catalogLatestUpdatedAt: TimeInterval = 0,
        upstreamSessions: [SessionLinkedUpstreamSession]
    ) {
        self.machineID = machineID
        self.machineDisplayName = machineDisplayName
        self.wrappedMachineDataEncryptionKey = wrappedMachineDataEncryptionKey
        self.projectPath = projectPath
        self.projectDisplayPath = projectDisplayPath ?? projectPath
        self.hasConcreteProjectPath = hasConcreteProjectPath
        self.catalogSessionCount = max(0, catalogSessionCount)
        self.catalogLatestUpdatedAt = max(0, catalogLatestUpdatedAt)
        self.upstreamSessions = upstreamSessions
    }

    public var id: String {
        "\(machineID)|\(projectPath)"
    }

    public var title: String {
        let normalized = projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "Project" }
        let lastComponent = (normalized as NSString).lastPathComponent
        return lastComponent.isEmpty ? normalized : lastComponent
    }

    public var latestUpdatedAt: TimeInterval {
        let upstreamTimestamp = displayUpstreamSessions.map(\.sortTimestamp).max() ?? 0
        return max(upstreamTimestamp, catalogLatestUpdatedAt)
    }

    public var allSessionCount: Int {
        max(displayUpstreamSessions.count, catalogSessionCount)
    }

    public var displayUpstreamSessions: [SessionLinkedUpstreamSession] {
        upstreamSessions
    }
}

public extension SessionListPresentationBuilder {
    static func projectGroup(
        id: String,
        sessions: [APISession],
        upstreamSessions: [SessionLinkedUpstreamSession],
        projects: [SessionMachineProject] = []
    ) -> SessionProjectGroup? {
        projectGroups(
            sessions: sessions,
            upstreamSessions: upstreamSessions,
            projects: projects
        ).first(where: { $0.id == id })
    }

    static func projectGroups(
        sessions: [APISession],
        upstreamSessions: [SessionLinkedUpstreamSession],
        projects: [SessionMachineProject] = []
    ) -> [SessionProjectGroup] {
        let explicitProjects = projects.filter(\.summary.openedExplicitly)
        guard !explicitProjects.isEmpty else { return [] }

        struct Accumulator {
            var machineDisplayName: String
            var wrappedMachineDataEncryptionKey: String?
            var projectPath: String
            var projectDisplayPath: String
            var hasConcreteProjectPath: Bool
            var catalogSessionCount: Int
            var catalogLatestUpdatedAt: TimeInterval
            var upstreamSessions: [SessionLinkedUpstreamSession] = []
        }

        var groups: [String: Accumulator] = [:]

        for project in explicitProjects {
            let rawProjectPath = project.summary.path.trimmingCharacters(in: .whitespacesAndNewlines)
            let projectPath = normalizedProjectPath(rawProjectPath) ?? rawProjectPath
            let trimmedDisplayPath = project.summary.displayPath?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let projectDisplayPath = (trimmedDisplayPath?.isEmpty == false ? trimmedDisplayPath : nil) ?? projectPath
            guard !projectPath.isEmpty else { continue }
            let key = "\(project.machineID)|\(projectPath)"
            if groups[key] == nil {
                groups[key] = Accumulator(
                    machineDisplayName: project.machineDisplayName,
                    wrappedMachineDataEncryptionKey: project.wrappedMachineDataEncryptionKey,
                    projectPath: projectPath,
                    projectDisplayPath: projectDisplayPath,
                    hasConcreteProjectPath: true,
                    catalogSessionCount: max(0, project.summary.codexThreadCount + project.summary.claudeSessionCount),
                    catalogLatestUpdatedAt: parseISO8601(project.summary.latestUpdatedAt)?.timeIntervalSince1970 ?? 0
                )
            } else if project.summary.openedExplicitly, var accumulator = groups[key] {
                accumulator.machineDisplayName = SessionMachineDisplayNameResolver.preferred(
                    existing: accumulator.machineDisplayName,
                    candidate: project.machineDisplayName,
                    machineID: project.machineID
                )
                if accumulator.wrappedMachineDataEncryptionKey == nil {
                    accumulator.wrappedMachineDataEncryptionKey = project.wrappedMachineDataEncryptionKey
                }
                accumulator.projectDisplayPath = projectDisplayPath
                accumulator.hasConcreteProjectPath = true
                accumulator.catalogSessionCount = max(
                    accumulator.catalogSessionCount,
                    max(0, project.summary.codexThreadCount + project.summary.claudeSessionCount)
                )
                accumulator.catalogLatestUpdatedAt = max(
                    accumulator.catalogLatestUpdatedAt,
                    parseISO8601(project.summary.latestUpdatedAt)?.timeIntervalSince1970 ?? 0
                )
                groups[key] = accumulator
            }
        }

        for row in upstreamSessions {
            let normalizedPath = normalizedProjectPath(row.summary.cwd)
            let projectPath = normalizedPath ?? "No Project Context"
            let key = "\(row.machineID)|\(projectPath)"
            guard var accumulator = groups[key] else { continue }
            accumulator.machineDisplayName = SessionMachineDisplayNameResolver.preferred(
                existing: accumulator.machineDisplayName,
                candidate: row.machineDisplayName,
                machineID: row.machineID
            )
            accumulator.upstreamSessions.append(row)
            groups[key] = accumulator
        }

        return groups.map { key, value in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            return SessionProjectGroup(
                machineID: parts.first ?? value.machineDisplayName,
                machineDisplayName: value.machineDisplayName,
                wrappedMachineDataEncryptionKey: value.wrappedMachineDataEncryptionKey,
                projectPath: value.projectPath,
                projectDisplayPath: value.projectDisplayPath,
                hasConcreteProjectPath: value.hasConcreteProjectPath,
                catalogSessionCount: value.catalogSessionCount,
                catalogLatestUpdatedAt: value.catalogLatestUpdatedAt,
                upstreamSessions: value.upstreamSessions.sorted(by: compareUpstreamSessions)
            )
        }
        .sorted(by: compareProjectGroups)
    }

    private static func normalizedProjectPath(_ raw: String?) -> String? {
        SessionProjectPathCanonicalizer.canonicalPath(raw)
    }

    private static func compareProjectGroups(_ lhs: SessionProjectGroup, _ rhs: SessionProjectGroup) -> Bool {
        if lhs.latestUpdatedAt != rhs.latestUpdatedAt {
            return lhs.latestUpdatedAt > rhs.latestUpdatedAt
        }
        if lhs.machineDisplayName != rhs.machineDisplayName {
            return lhs.machineDisplayName.localizedCaseInsensitiveCompare(rhs.machineDisplayName) == .orderedAscending
        }
        return lhs.projectPath.localizedCaseInsensitiveCompare(rhs.projectPath) == .orderedAscending
    }
    private static func compareUpstreamSessions(
        _ lhs: SessionLinkedUpstreamSession,
        _ rhs: SessionLinkedUpstreamSession
    ) -> Bool {
        if lhs.sortTimestamp != rhs.sortTimestamp {
            return lhs.sortTimestamp > rhs.sortTimestamp
        }
        return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
    }

    private static func parseISO8601(_ value: String) -> Date? {
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

private func compareUpstreamSession(
    _ lhs: SessionLinkedUpstreamSession,
    _ rhs: SessionLinkedUpstreamSession
) -> Bool {
    if lhs.sortTimestamp != rhs.sortTimestamp {
        return lhs.sortTimestamp > rhs.sortTimestamp
    }
    return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
}
