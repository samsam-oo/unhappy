import Foundation
import CoreKit

public struct SessionRecentSection: Equatable, Identifiable, Sendable {
    public enum Entry: Identifiable, Equatable, Sendable {
        case direct(DirectSessionIdentity, updatedAt: TimeInterval)

        public var id: String {
            switch self {
            case .direct(let identity, _):
                return "direct:\(identity.machineID)|\(identity.provider.rawValue)|\(identity.upstreamSessionID)"
            }
        }

        public var updatedAt: TimeInterval {
            switch self {
            case .direct(_, let updatedAt):
                return updatedAt
            }
        }
    }

    public let dayStart: Date
    public let title: String
    public let entries: [Entry]

    public var id: TimeInterval { dayStart.timeIntervalSince1970 }
}

public enum SessionRecentPresentationBuilder {
    public static func make(
        upstreamSessions: [SessionLinkedUpstreamSession],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [SessionRecentSection] {
        let directPairs: [(String, SessionRecentSection.Entry)] = upstreamSessions.compactMap { row in
            guard let identity = DirectSessionIdentityResolver.resolve(from: row) else {
                return nil
            }
            return (row.id, SessionRecentSection.Entry.direct(identity, updatedAt: row.sortTimestamp))
        }
        let directRowsByKey = Dictionary(uniqueKeysWithValues: directPairs)

        let entries: [SessionRecentSection.Entry] = Array(directRowsByKey.values)

        guard !entries.isEmpty else { return [] }

        let sorted = entries.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }

        var grouped: [Date: [SessionRecentSection.Entry]] = [:]
        for entry in sorted {
            let date = Date(timeIntervalSince1970: entry.updatedAt)
            let dayStart = calendar.startOfDay(for: date)
            grouped[dayStart, default: []].append(entry)
        }

        let todayStart = calendar.startOfDay(for: now)
        let dayStarts = grouped.keys.sorted(by: >)
        return dayStarts.map { dayStart in
            SessionRecentSection(
                dayStart: dayStart,
                title: sectionTitle(for: dayStart, todayStart: todayStart, calendar: calendar),
                entries: grouped[dayStart] ?? []
            )
        }
    }

    public static func sectionTitle(
        for dayStart: Date,
        todayStart: Date,
        calendar: Calendar
    ) -> String {
        if calendar.isDate(dayStart, inSameDayAs: todayStart) {
            return "Today"
        }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart) else {
            return "Yesterday"
        }
        if calendar.isDate(dayStart, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let days = calendar.dateComponents([.day], from: dayStart, to: todayStart).day ?? 0
        if days <= 0 {
            return "Today"
        }
        return "\(days) days ago"
    }
}
