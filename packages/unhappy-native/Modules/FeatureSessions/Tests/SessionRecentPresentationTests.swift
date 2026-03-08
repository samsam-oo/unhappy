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
            upstreamSessions: [],
            now: now,
            calendar: calendar
        )

        #expect(sections.count == 2)
        #expect(sections.first?.entries.map(\.id) == ["mirrored:today-1", "mirrored:today-2"])
        #expect(sections.last?.entries.map(\.id) == ["mirrored:older-1"])
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
            sessions: [],
            upstreamSessions: []
        )
        #expect(sections.isEmpty)
    }

    @Test
    func makePrefersDirectProviderRowsOverMirroredSessions() {
        let mirrored = makeSession(
            id: "session-1",
            updatedAt: 1_700_000_000,
            metadata: #"{"machineId":"machine-1","flavor":"codex","agentSessionId":"thread-1","cwd":"/repo/app"}"#
        )
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
            sessions: [mirrored],
            upstreamSessions: [upstream],
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(sections.count == 1)
        #expect(sections.first?.entries.map(\.id) == ["direct:machine-1|codex|thread-1"])
    }
}

private func makeSession(
    id: String,
    updatedAt: TimeInterval,
    metadata: String = "enc"
) -> APISession {
    APISession(
        id: id,
        displayName: nil,
        seq: nil,
        active: true,
        activeAt: updatedAt,
        createdAt: updatedAt - 60,
        updatedAt: updatedAt,
        metadataVersion: 1,
        metadata: metadata,
        agentState: nil,
        agentStateVersion: nil,
        dataEncryptionKey: nil,
        lastMessage: nil
    )
}
