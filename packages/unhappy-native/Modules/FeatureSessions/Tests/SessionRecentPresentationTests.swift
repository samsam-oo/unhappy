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

        let sessions = [
            makeSession(id: "today-1", updatedAt: 1_700_000_000),
            makeSession(id: "today-2", updatedAt: 1_699_999_000),
            makeSession(id: "older-1", updatedAt: 1_699_840_000),
        ]

        let sections = SessionRecentPresentationBuilder.make(
            sessions: sessions,
            now: now,
            calendar: calendar
        )

        #expect(sections.count == 2)
        #expect(sections.first?.sessions.map(\.id) == ["today-1", "today-2"])
        #expect(sections.last?.sessions.map(\.id) == ["older-1"])
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
        let sections = SessionRecentPresentationBuilder.make(sessions: [])
        #expect(sections.isEmpty)
    }
}

private func makeSession(id: String, updatedAt: TimeInterval) -> APISession {
    APISession(
        id: id,
        displayName: nil,
        seq: nil,
        active: true,
        activeAt: updatedAt,
        createdAt: updatedAt - 60,
        updatedAt: updatedAt,
        metadataVersion: 1,
        metadata: "enc",
        agentState: nil,
        agentStateVersion: nil,
        dataEncryptionKey: nil,
        lastMessage: nil
    )
}
