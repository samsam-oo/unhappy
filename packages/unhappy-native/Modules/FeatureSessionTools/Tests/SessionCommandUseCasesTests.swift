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

    @Test
    func runBashThrowsMissingCommand() async {
        let useCase = SessionBashUseCase(
            service: BashService(result: .init(success: true, stdout: "", stderr: "", exitCode: 0, error: nil))
        )

        await #expect(throws: SessionCommandError.missingCommand) {
            _ = try await useCase.runBash(
                serverURLString: "https://api.unhappy.im",
                token: "token",
                sessionID: "session-1",
                command: "   ",
                cwd: nil,
                timeout: nil
            )
        }
    }

    @Test
    func runRipgrepReturnsOutputWhenSuccessful() async throws {
        let useCase = SessionRipgrepUseCase(
            service: RipgrepService(result: .init(success: true, stdout: "Sources/App.swift:12:TODO", stderr: "", exitCode: 0, error: nil))
        )

        let result = try await useCase.runRipgrep(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            sessionID: "session-1",
            args: ["TODO", "Sources"],
            cwd: "/tmp/work"
        )

        #expect(result.success == true)
        #expect(result.stdout.contains("TODO"))
        #expect(result.exitCode == 0)
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

private struct BashService: SessionBashRunning {
    let result: APISessionBashResult

    func runBash(
        serverURL: URL,
        token: String,
        sessionID: String,
        command: String,
        cwd: String?,
        timeout: Int?
    ) async throws -> APISessionBashResult {
        result
    }
}

private struct RipgrepService: SessionRipgrepRunning {
    let result: APISessionBashResult

    func runRipgrep(
        serverURL: URL,
        token: String,
        sessionID: String,
        args: [String],
        cwd: String?
    ) async throws -> APISessionBashResult {
        result
    }
}
