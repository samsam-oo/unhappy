import Foundation
import CoreKit

public enum SessionListEntry: Identifiable, Equatable, Sendable {
    case mirroredSession(APISession)
    case upstreamSession(SessionLinkedUpstreamSession)

    public var id: String {
        switch self {
        case .mirroredSession(let session):
            return "session:\(session.id)"
        case .upstreamSession(let row):
            return "upstream:\(row.id)"
        }
    }

    public var updatedAt: TimeInterval {
        switch self {
        case .mirroredSession(let session):
            return session.updatedAt
        case .upstreamSession(let row):
            return row.sortTimestamp
        }
    }
}

public enum SessionListPresentationBuilder {
    public static func machineEntries(
        sessions: [APISession],
        upstreamSessions: [SessionLinkedUpstreamSession]
    ) -> [SessionListEntry] {
        let mirrored = sessions.compactMap { session -> SessionListEntry? in
            guard SessionUpstreamIdentity(session: session) != nil else { return nil }
            return .mirroredSession(session)
        }
        let upstream = upstreamSessions.map(SessionListEntry.upstreamSession)
        return (mirrored + upstream).sorted(by: compareEntries)
    }

    public static func localSessions(
        from sessions: [APISession]
    ) -> [APISession] {
        sessions
            .filter { SessionUpstreamIdentity(session: $0) == nil }
            .sorted(by: compareSessions)
    }

    private static func compareEntries(_ lhs: SessionListEntry, _ rhs: SessionListEntry) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
    }

    private static func compareSessions(_ lhs: APISession, _ rhs: APISession) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
    }
}
