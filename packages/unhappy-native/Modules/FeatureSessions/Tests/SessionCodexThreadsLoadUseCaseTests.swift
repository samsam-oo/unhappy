import Foundation
import Testing
@testable import FeatureSessions
import CoreKit

struct SessionCodexThreadsLoadUseCaseTests {
    @Test
    func loadCodexThreadsReturnsRowsFromService() async throws {
        let expected = [
            APICodexThreadSummary(
                id: "thread-1",
                name: "Refactor",
                cwd: "/tmp/repo",
                updatedAt: "2026-02-24T10:00:00.000Z",
                createdAt: "2026-02-24T09:00:00.000Z",
                archived: false
            )
        ]
        let useCase = SessionCodexThreadsLoadUseCase(
            service: MockCodexThreadsService(result: .success(expected))
        )

        let rows = try await useCase.loadCodexThreads(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            sessionID: "session-1",
            limit: 20
        )

        #expect(rows == expected)
    }

    @Test
    func loadCodexThreadsWithoutTokenThrowsValidationError() async throws {
        let useCase = SessionCodexThreadsLoadUseCase(
            service: MockCodexThreadsService(result: .success([]))
        )

        await #expect(throws: SessionCodexThreadsLoadingError.missingToken) {
            _ = try await useCase.loadCodexThreads(
                serverURLString: "https://api.unhappy.im",
                token: "   ",
                sessionID: "session-1",
                limit: 20
            )
        }
    }
}

private enum MockCodexThreadsServiceError: Error, Sendable {
    case failed
}

private struct MockCodexThreadsService: SessionCodexThreadsFetching {
    let result: Result<[APICodexThreadSummary], MockCodexThreadsServiceError>

    func fetchCodexThreads(serverURL: URL, token: String, sessionID: String, limit: Int) async throws -> [APICodexThreadSummary] {
        switch result {
        case .success(let rows):
            return rows
        case .failure(let error):
            throw error
        }
    }
}
