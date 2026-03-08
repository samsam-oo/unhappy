import Foundation
import CoreKit

struct SessionRecentSection: Equatable, Identifiable, Sendable {
    enum Entry: Identifiable, Equatable, Sendable {
        case direct(SessionLinkedUpstreamSession)
        case mirrored(APISession)

        var id: String {
            switch self {
            case .direct(let row):
                return "direct:\(row.id)"
            case .mirrored(let session):
                return "mirrored:\(session.id)"
            }
        }

        var updatedAt: TimeInterval {
            switch self {
            case .direct(let row):
                return row.sortTimestamp
            case .mirrored(let session):
                return session.updatedAt
            }
        }
    }

    let dayStart: Date
    let title: String
    let entries: [Entry]

    var id: TimeInterval { dayStart.timeIntervalSince1970 }
}

enum SessionRecentPresentationBuilder {
    static func make(
        sessions: [APISession],
        upstreamSessions: [SessionLinkedUpstreamSession],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [SessionRecentSection] {
        let directRowsByKey = Dictionary(
            uniqueKeysWithValues: upstreamSessions.map { ($0.id, $0) }
        )

        var entries: [SessionRecentSection.Entry] = upstreamSessions.map(SessionRecentSection.Entry.direct)

        for session in sessions {
            if let key = SessionUpstreamIdentity(session: session)?.key,
               directRowsByKey[key] != nil {
                continue
            }
            entries.append(.mirrored(session))
        }

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

    static func sectionTitle(
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
