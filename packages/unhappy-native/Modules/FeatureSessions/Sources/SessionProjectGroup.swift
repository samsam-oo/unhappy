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
        let mirroredTimestamp = displayMirroredSessions.map(\.updatedAt).max() ?? 0
        let upstreamTimestamp = displayUpstreamSessions.map(\.sortTimestamp).max() ?? 0
        return max(mirroredTimestamp, upstreamTimestamp, catalogLatestUpdatedAt)
    }

    public var activeSessionCount: Int {
        displayMirroredSessions.filter(\.active).count
    }

    public var allSessionCount: Int {
        max(displayMirroredSessions.count + displayUpstreamSessions.count, catalogSessionCount)
    }

    public var displayMirroredSessions: [APISession] {
        logicalProjection.mirroredSessions
    }

    public var displayUpstreamSessions: [SessionLinkedUpstreamSession] {
        logicalProjection.upstreamSessions
    }

    private var logicalProjection: LogicalProjection {
        makeLogicalProjection(
            mirroredSessions: mirroredSessions,
            upstreamSessions: upstreamSessions
        )
    }
}

private struct LogicalProjection {
    let mirroredSessions: [APISession]
    let upstreamSessions: [SessionLinkedUpstreamSession]
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
            var projectPath: String
            var hasConcreteProjectPath: Bool
            var catalogSessionCount: Int
            var catalogLatestUpdatedAt: TimeInterval
            var mirroredSessions: [APISession] = []
            var upstreamSessions: [SessionLinkedUpstreamSession] = []
        }

        var groups: [String: Accumulator] = [:]

        for project in explicitProjects {
            let rawProjectPath = project.summary.path.trimmingCharacters(in: .whitespacesAndNewlines)
            let projectPath = normalizedProjectPath(rawProjectPath) ?? rawProjectPath
            guard !projectPath.isEmpty else { continue }
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
            let normalizedPath = normalizedProjectPath(context.workingDirectory)
            let projectPath = normalizedPath ?? "No Project Context"
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

private func makeLogicalProjection(
    mirroredSessions: [APISession],
    upstreamSessions: [SessionLinkedUpstreamSession]
) -> LogicalProjection {
    var upstreamByKey: [String: SessionLinkedUpstreamSession] = [:]
    for row in upstreamSessions {
        if let existing = upstreamByKey[row.id] {
            if compareUpstreamSession(row, existing) {
                upstreamByKey[row.id] = row
            }
        } else {
            upstreamByKey[row.id] = row
        }
    }

    var mirroredByKey: [String: APISession] = [:]
    for session in mirroredSessions {
        let key = SessionUpstreamIdentity(session: session)?.key ?? "mirrored:\(session.id)"
        if upstreamByKey[key] != nil {
            continue
        }
        if let existing = mirroredByKey[key] {
            if compareMirroredSession(session, existing) {
                mirroredByKey[key] = session
            }
        } else {
            mirroredByKey[key] = session
        }
    }

    return LogicalProjection(
        mirroredSessions: mirroredByKey.values.sorted(by: compareMirroredSession),
        upstreamSessions: upstreamByKey.values.sorted(by: compareUpstreamSession)
    )
}

private func compareMirroredSession(_ lhs: APISession, _ rhs: APISession) -> Bool {
    if lhs.active != rhs.active {
        return lhs.active && !rhs.active
    }
    if lhs.updatedAt != rhs.updatedAt {
        return lhs.updatedAt > rhs.updatedAt
    }
    return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
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
