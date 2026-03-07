import Foundation
import Testing
@testable import FeatureSessions
import CoreKit

struct SessionSpawnUseCaseTests {
    @Test
    func spawnSessionReturnsServiceResponse() async throws {
        let expected = APISessionSpawnResult(
            success: true,
            sessionID: "session-new",
            requiresUserApproval: nil,
            actionRequired: nil,
            directory: nil,
            error: nil
        )
        let useCase = SessionSpawnUseCase(
            service: MockSessionSpawnService(result: .success(expected))
        )

        let response = try await useCase.spawnSession(
            SessionSpawnRequest(
                serverURLString: "https://api.unhappy.im",
                token: "token",
                sessionID: "session-1",
                directory: "/tmp/work",
                agent: .claude,
                codexResumeThreadID: nil,
                claudeResumeSessionID: "c7a2f5d1-1111-2222-3333-444444444444",
                approvedNewDirectoryCreation: true
            )
        )

        #expect(response == expected)
    }

    @Test
    func spawnSessionWithoutTokenThrowsValidationError() async throws {
        let useCase = SessionSpawnUseCase(
            service: MockSessionSpawnService(
                result: .success(
                    APISessionSpawnResult(
                        success: true,
                        sessionID: "session-new",
                        requiresUserApproval: nil,
                        actionRequired: nil,
                        directory: nil,
                        error: nil
                    )
                )
            )
        )

        await #expect(throws: SessionSpawnError.missingToken) {
            _ = try await useCase.spawnSession(
                SessionSpawnRequest(
                    serverURLString: "https://api.unhappy.im",
                    token: "  ",
                    sessionID: "session-1",
                    directory: "/tmp/work",
                    agent: .claude,
                    codexResumeThreadID: nil,
                    claudeResumeSessionID: nil,
                    approvedNewDirectoryCreation: nil
                )
            )
        }
    }

    @Test
    func spawnSessionRequiresApprovalThrowsApprovalError() async throws {
        let approvalResponse = APISessionSpawnResult(
            success: false,
            sessionID: nil,
            requiresUserApproval: true,
            actionRequired: "CREATE_DIRECTORY",
            directory: "/tmp/new-dir",
            error: nil
        )
        let useCase = SessionSpawnUseCase(
            service: MockSessionSpawnService(result: .success(approvalResponse))
        )

        await #expect(throws: SessionSpawnError.requiresUserApproval(directory: "/tmp/new-dir")) {
            _ = try await useCase.spawnSession(
                SessionSpawnRequest(
                    serverURLString: "https://api.unhappy.im",
                    token: "token",
                    sessionID: "session-1",
                    directory: "/tmp/new-dir",
                    agent: .claude,
                    codexResumeThreadID: nil,
                    claudeResumeSessionID: "resume-id",
                    approvedNewDirectoryCreation: false
                )
            )
        }
    }
}

private enum MockSessionSpawnServiceError: Error, Sendable {
    case failed
}

private struct MockSessionSpawnService: SessionSpawning {
    let result: Result<APISessionSpawnResult, MockSessionSpawnServiceError>

    func spawnSession(
        serverURL: URL,
        token: String,
        sessionID: String,
        directory: String,
        agent: APISessionSpawnAgent?,
        codexResumeThreadID: String?,
        claudeResumeSessionID: String?,
        approvedNewDirectoryCreation: Bool?
    ) async throws -> APISessionSpawnResult {
        switch result {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
}
