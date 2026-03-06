import Foundation
import CoreKit

public struct SessionProjectGroup: Identifiable, Equatable, Sendable {
    public let machineID: String
    public let machineDisplayName: String
    public let projectPath: String
    public let hasConcreteProjectPath: Bool
    public let mirroredSessions: [APISession]
    public let upstreamSessions: [SessionLinkedUpstreamSession]

    public init(
        machineID: String,
        machineDisplayName: String,
        projectPath: String,
        hasConcreteProjectPath: Bool,
        mirroredSessions: [APISession],
        upstreamSessions: [SessionLinkedUpstreamSession]
    ) {
        self.machineID = machineID
        self.machineDisplayName = machineDisplayName
        self.projectPath = projectPath
        self.hasConcreteProjectPath = hasConcreteProjectPath
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
        return max(mirroredTimestamp, upstreamTimestamp)
    }

    public var activeSessionCount: Int {
        mirroredSessions.filter(\.active).count
    }

    public var allSessionCount: Int {
        mirroredSessions.count + upstreamSessions.count
    }
}

public extension SessionListPresentationBuilder {
    static func projectGroups(
        sessions: [APISession],
        upstreamSessions: [SessionLinkedUpstreamSession],
        projects: [SessionMachineProject] = []
    ) -> [SessionProjectGroup] {
        struct Accumulator {
            var machineDisplayName: String
            var projectPath: String
            var hasConcreteProjectPath: Bool
            var mirroredSessions: [APISession] = []
            var upstreamSessions: [SessionLinkedUpstreamSession] = []
        }

        var groups: [String: Accumulator] = [:]

        for session in sessions {
            let context = SessionRuntimeContext(session: session)
            let machineID = context.machineID ?? "local"
            let machineDisplayName = context.machineDisplayName ?? context.machineID ?? "Local"
            let projectPath = normalizedProjectPath(context.workingDirectory) ?? "No Project Context"
            let hasConcreteProjectPath = normalizedProjectPath(context.workingDirectory) != nil
            let key = "\(machineID)|\(projectPath)"
            if groups[key] == nil {
                groups[key] = Accumulator(
                    machineDisplayName: machineDisplayName,
                    projectPath: projectPath,
                    hasConcreteProjectPath: hasConcreteProjectPath
                )
            }
            groups[key]?.mirroredSessions.append(session)
        }

        for row in upstreamSessions {
            let projectPath = normalizedProjectPath(row.summary.cwd) ?? "No Project Context"
            let key = "\(row.machineID)|\(projectPath)"
            if groups[key] == nil {
                groups[key] = Accumulator(
                    machineDisplayName: row.machineDisplayName,
                    projectPath: projectPath,
                    hasConcreteProjectPath: normalizedProjectPath(row.summary.cwd) != nil
                )
            }
            groups[key]?.upstreamSessions.append(row)
        }

        for project in projects {
            let projectPath = normalizedProjectPath(project.summary.path) ?? project.summary.path
            let key = "\(project.machineID)|\(projectPath)"
            if groups[key] == nil {
                groups[key] = Accumulator(
                    machineDisplayName: project.machineDisplayName,
                    projectPath: projectPath,
                    hasConcreteProjectPath: true
                )
            } else if project.summary.openedExplicitly {
                groups[key]?.hasConcreteProjectPath = true
            }
        }

        return groups.map { key, value in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            return SessionProjectGroup(
                machineID: parts.first ?? value.machineDisplayName,
                machineDisplayName: value.machineDisplayName,
                projectPath: value.projectPath,
                hasConcreteProjectPath: value.hasConcreteProjectPath,
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
}
