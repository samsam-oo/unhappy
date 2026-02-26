import Foundation
import Testing
import CoreKit
@testable import FeatureSettings

struct SettingsUsageUseCaseTests {
    @Test
    func loadUsageAggregatesSessionCounts() async throws {
        let sessions = [
            APISession(
                id: "s1",
                active: true,
                activeAt: 10,
                createdAt: 1,
                updatedAt: 100,
                metadataVersion: 1,
                metadata: "",
                dataEncryptionKey: nil,
                lastMessage: nil
            ),
            APISession(
                id: "s2",
                active: false,
                activeAt: 11,
                createdAt: 1,
                updatedAt: 200,
                metadataVersion: 1,
                metadata: "",
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let useCase = SettingsUsageLoadUseCase(service: SessionsService(sessions: sessions))

        let snapshot = try await useCase.loadUsage(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(snapshot.totalSessions == 2)
        #expect(snapshot.activeSessions == 1)
        #expect(snapshot.inactiveSessions == 1)
        #expect(snapshot.lastUpdatedAt == 200)
    }

    @Test
    func loadUsageThrowsMissingToken() async {
        let useCase = SettingsUsageLoadUseCase(service: SessionsService(sessions: []))

        await #expect(throws: SettingsUsageError.missingToken) {
            _ = try await useCase.loadUsage(
                serverURLString: "https://api.unhappy.im",
                token: " "
            )
        }
    }
}

private struct SessionsService: SessionsFetching {
    let sessions: [APISession]

    func fetchSessions(serverURL: URL, token: String) async throws -> [APISession] {
        sessions
    }

    func fetchSessionsPage(
        serverURL: URL,
        token: String,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionsPage {
        APISessionsPage(sessions: sessions, nextCursor: nil, hasNext: false)
    }
}
