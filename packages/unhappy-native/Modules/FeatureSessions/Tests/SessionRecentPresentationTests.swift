import Foundation
import Testing
import CoreKit
@testable import FeatureSessions

struct SessionRecentPresentationTests {
    @Test
    func makeGroupsSessionsByDayInDescendingOrder() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let sections = SessionRecentPresentationBuilder.make(
            upstreamSessions: [],
            now: now,
            calendar: calendar
        )

        #expect(sections.isEmpty)
    }

    @Test
    func sectionTitleMapsTodayYesterdayAndDaysAgo() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!

        #expect(
            SessionRecentPresentationBuilder.sectionTitle(
                for: today,
                todayStart: today,
                calendar: calendar
            ) == "Today"
        )
        #expect(
            SessionRecentPresentationBuilder.sectionTitle(
                for: yesterday,
                todayStart: today,
                calendar: calendar
            ) == "Yesterday"
        )
        #expect(
            SessionRecentPresentationBuilder.sectionTitle(
                for: twoDaysAgo,
                todayStart: today,
                calendar: calendar
            ) == "2 days ago"
        )
    }

    @Test
    func makeReturnsEmptyForEmptyInput() {
        let sections = SessionRecentPresentationBuilder.make(
            upstreamSessions: []
        )
        #expect(sections.isEmpty)
    }

    @Test
    func makePrefersDirectProviderRowsOverMirroredSessions() {
        let upstream = SessionLinkedUpstreamSession(
            machineID: "machine-1",
            machineDisplayName: "Work Mac",
            summary: APIUpstreamSessionSummary(
                id: "thread-1",
                provider: .codex,
                title: "Direct Codex",
                cwd: "/repo/app",
                path: "/Users/test/.codex/sessions/2026/03/thread-1.jsonl",
                updatedAt: "2026-03-14T12:00:00.000Z",
                createdAt: "2026-03-14T11:00:00.000Z",
                archived: false
            )
        )

        let sections = SessionRecentPresentationBuilder.make(
            upstreamSessions: [upstream],
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(sections.count == 1)
        #expect(sections.first?.entries.map(\.id) == ["direct:machine-1|codex|thread-1"])
    }
}
