import Foundation
import Testing
@testable import FeatureSessionTools
import CoreKit

struct SessionCommandUseCasesTests {
    @Test
    func abortTaskThrowsMissingToken() async {
        let useCase = SessionTaskAbortUseCase(
            service: AbortService(result: .init(success: true, error: nil))
        )

        await #expect(throws: SessionCommandError.missingToken) {
            _ = try await useCase.abortTask(
                serverURLString: "https://api.unhappy.im",
                token: " ",
                sessionID: "session-1",
                reason: nil
            )
        }
    }

    @Test
    func abortTaskReturnsResultWhenSuccessful() async throws {
        let useCase = SessionTaskAbortUseCase(
            service: AbortService(result: .init(success: true, error: nil))
        )

        let result = try await useCase.abortTask(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            sessionID: "session-1",
            reason: "user-requested"
        )

        #expect(result.success == true)
    }

    @Test
    func respondPermissionThrowsMissingRequestID() async {
        let useCase = SessionPermissionUseCase(
            service: PermissionService(result: .init(success: true, error: nil))
        )

        await #expect(throws: SessionCommandError.missingPermissionRequestID) {
            _ = try await useCase.respondPermission(
                serverURLString: "https://api.unhappy.im",
                token: "token",
                sessionID: "session-1",
                permissionRequestID: " ",
                approved: true,
                mode: .default,
                allowTools: nil,
                decision: .approved
            )
        }
    }

    @Test
    func switchModeReturnsSwitchedFlag() async throws {
        let useCase = SessionModeSwitchUseCase(
            service: SwitchService(result: .init(success: true, switched: true, error: nil))
        )

        let result = try await useCase.switchMode(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            sessionID: "session-1",
            to: .local
        )

        #expect(result.success == true)
        #expect(result.switched == true)
    }
}

private struct AbortService: SessionAborting {
    let result: APISessionCommandResult

    func abortSessionTask(
        serverURL: URL,
        token: String,
        sessionID: String,
        reason: String?
    ) async throws -> APISessionCommandResult {
        result
    }
}

private struct PermissionService: SessionPermissionResponding {
    let result: APISessionCommandResult

    func respondPermission(
        serverURL: URL,
        token: String,
        sessionID: String,
        permissionRequestID: String,
        approved: Bool,
        mode: APISessionPermissionMode?,
        allowTools: [String]?,
        decision: APISessionPermissionDecision?
    ) async throws -> APISessionCommandResult {
        result
    }
}

private struct SwitchService: SessionModeSwitching {
    let result: APISessionSwitchResult

    func switchSessionMode(
        serverURL: URL,
        token: String,
        sessionID: String,
        to: APISessionSwitchTarget
    ) async throws -> APISessionSwitchResult {
        result
    }
}
