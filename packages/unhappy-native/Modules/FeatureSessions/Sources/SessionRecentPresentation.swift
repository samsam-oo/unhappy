import Foundation
import CoreKit

struct SessionRecentSection: Equatable, Identifiable, Sendable {
    let dayStart: Date
    let title: String
    let sessions: [APISession]

    var id: TimeInterval { dayStart.timeIntervalSince1970 }
}

enum SessionRecentPresentationBuilder {
    static func make(
        sessions: [APISession],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [SessionRecentSection] {
        guard !sessions.isEmpty else { return [] }
        let sorted = sessions.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }

        var grouped: [Date: [APISession]] = [:]
        for session in sorted {
            let date = Date(timeIntervalSince1970: session.updatedAt)
            let dayStart = calendar.startOfDay(for: date)
            grouped[dayStart, default: []].append(session)
        }

        let todayStart = calendar.startOfDay(for: now)
        let dayStarts = grouped.keys.sorted(by: >)
        return dayStarts.map { dayStart in
            SessionRecentSection(
                dayStart: dayStart,
                title: sectionTitle(for: dayStart, todayStart: todayStart, calendar: calendar),
                sessions: grouped[dayStart] ?? []
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
