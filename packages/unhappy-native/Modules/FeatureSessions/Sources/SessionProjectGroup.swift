import Foundation
import CoreKit

public enum SessionListPresentationBuilder {}

public struct SessionProjectGroup: Identifiable, Equatable, Sendable {
    public let machineID: String
    public let machineDisplayName: String
    public let projectPath: String
    public let hasConcreteProjectPath: Bool
    public let catalogSessionCount: Int
    public let catalogLatestUpdatedAt: TimeInterval
    public let mirroredSessions: [APISession]
    public let upstreamSessions: [SessionLinkedUpstreamSession]

    public init(
        machineID: String,
        machineDisplayName: String,
        projectPath: String,
        hasConcreteProjectPath: Bool,
        catalogSessionCount: Int = 0,
        catalogLatestUpdatedAt: TimeInterval = 0,
        mirroredSessions: [APISession],
        upstreamSessions: [SessionLinkedUpstreamSession]
    ) {
        self.machineID = machineID
        self.machineDisplayName = machineDisplayName
        self.projectPath = projectPath
        self.hasConcreteProjectPath = hasConcreteProjectPath
        self.catalogSessionCount = max(0, catalogSessionCount)
        self.catalogLatestUpdatedAt = max(0, catalogLatestUpdatedAt)
        self.mirroredSessions = mirroredSessions
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
        let mirroredTimestamp = mirroredSessions.map(\.updatedAt).max() ?? 0
        let upstreamTimestamp = upstreamSessions.map(\.sortTimestamp).max() ?? 0
        return max(mirroredTimestamp, upstreamTimestamp, catalogLatestUpdatedAt)
    }

    public var activeSessionCount: Int {
        mirroredSessions.filter(\.active).count
    }

    public var allSessionCount: Int {
        max(mirroredSessions.count + upstreamSessions.count, catalogSessionCount)
    }
}

public extension SessionListPresentationBuilder {
    static func projectGroups(
        sessions: [APISession],
        upstreamSessions: [SessionLinkedUpstreamSession],
        projects: [SessionMachineProject] = []
    ) -> [SessionProjectGroup] {
        let explicitProjects = projects.filter(\.summary.openedExplicitly)
        guard !explicitProjects.isEmpty else { return [] }

        struct Accumulator {
            var machineDisplayName: String
            var projectPath: String
            var hasConcreteProjectPath: Bool
            var catalogSessionCount: Int
            var catalogLatestUpdatedAt: TimeInterval
            var mirroredSessions: [APISession] = []
            var upstreamSessions: [SessionLinkedUpstreamSession] = []
        }

        var groups: [String: Accumulator] = [:]

        for project in explicitProjects {
            let projectPath = normalizedProjectPath(project.summary.path) ?? project.summary.path
            let key = "\(project.machineID)|\(projectPath)"
            if groups[key] == nil {
                groups[key] = Accumulator(
                    machineDisplayName: project.machineDisplayName,
                    projectPath: projectPath,
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

        for session in sessions {
            let context = SessionRuntimeContext(session: session)
            let machineID = context.machineID ?? "local"
            let projectPath = normalizedProjectPath(context.workingDirectory) ?? "No Project Context"
            let key = "\(machineID)|\(projectPath)"
            guard var accumulator = groups[key] else { continue }
            accumulator.machineDisplayName = SessionMachineDisplayNameResolver.preferred(
                existing: accumulator.machineDisplayName,
                candidate: context.machineDisplayName,
                machineID: machineID
            )
            accumulator.mirroredSessions.append(session)
            groups[key] = accumulator
        }

        for row in upstreamSessions {
            let projectPath = normalizedProjectPath(row.summary.cwd) ?? "No Project Context"
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
                projectPath: value.projectPath,
                hasConcreteProjectPath: value.hasConcreteProjectPath,
                catalogSessionCount: value.catalogSessionCount,
                catalogLatestUpdatedAt: value.catalogLatestUpdatedAt,
                mirroredSessions: value.mirroredSessions.sorted(by: compareProjectSessions),
                upstreamSessions: value.upstreamSessions.sorted(by: compareUpstreamSessions)
            )
        }
        .sorted(by: compareProjectGroups)
    }

    private static func normalizedProjectPath(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        if raw == "/" {
            return raw
        }
        var normalized = raw
        while normalized.count > 1 && normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
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

    private static func compareProjectSessions(_ lhs: APISession, _ rhs: APISession) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
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
