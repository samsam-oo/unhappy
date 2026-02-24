import Foundation
import Testing
@testable import FeatureSessions
import CoreKit

struct SessionClaudeSessionsLoadUseCaseTests {
    @Test
    func loadClaudeSessionsReturnsRowsFromService() async throws {
        let expected = [
            APIClaudeSessionSummary(
                id: "a1b2c3d4-1111-2222-3333-444444444444",
                cwd: "/tmp/repo",
                updatedAt: "2026-02-24T10:00:00.000Z",
                createdAt: "2026-02-24T09:00:00.000Z"
            )
        ]
        let useCase = SessionClaudeSessionsLoadUseCase(
            service: MockClaudeSessionsService(result: .success(expected))
        )

        let rows = try await useCase.loadClaudeSessions(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            sessionID: "session-1",
            limit: 20,
            cwd: "/tmp/repo"
        )

        #expect(rows == expected)
    }

    @Test
    func loadClaudeSessionsWithoutTokenThrowsValidationError() async throws {
        let useCase = SessionClaudeSessionsLoadUseCase(
            service: MockClaudeSessionsService(result: .success([]))
        )

        await #expect(throws: SessionClaudeSessionsLoadingError.missingToken) {
            _ = try await useCase.loadClaudeSessions(
                serverURLString: "https://api.unhappy.im",
                token: "   ",
                sessionID: "session-1",
                limit: 20,
                cwd: nil
            )
        }
    }
}

private enum MockClaudeSessionsServiceError: Error, Sendable {
    case failed
}

private struct MockClaudeSessionsService: SessionClaudeSessionsFetching {
    let result: Result<[APIClaudeSessionSummary], MockClaudeSessionsServiceError>

    func fetchClaudeSessions(serverURL: URL, token: String, sessionID: String, limit: Int, cwd: String?) async throws -> [APIClaudeSessionSummary] {
        switch result {
        case .success(let rows):
            return rows
        case .failure(let error):
            throw error
        }
    }
}
