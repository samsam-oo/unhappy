import Foundation

enum SessionTimestampPresentation {
    static func updatedLabel(
        for unixTimeSeconds: TimeInterval,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        let date = Date(timeIntervalSince1970: unixTimeSeconds)
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
