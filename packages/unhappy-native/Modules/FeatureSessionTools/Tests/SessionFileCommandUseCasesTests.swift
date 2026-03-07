import Foundation
import Testing
@testable import FeatureSessionTools
import CoreKit

struct SessionFileCommandUseCasesTests {
    @Test
    func listDirectorySortsDirectoriesFirst() async throws {
        let entries = [
            APISessionDirectoryEntry(name: "main.swift", type: "file", size: 128, modified: nil),
            APISessionDirectoryEntry(name: "Sources", type: "directory", size: nil, modified: nil),
            APISessionDirectoryEntry(name: "Tests", type: "directory", size: nil, modified: nil)
        ]
        let useCase = SessionDirectoryListUseCase(
            service: DirectoryService(result: .init(success: true, entries: entries, error: nil))
        )

        let loaded = try await useCase.listDirectory(
            SessionDirectoryListRequest(
                serverURLString: "https://api.unhappy.im",
                token: "token",
                sessionID: "session-1",
                path: "/repo"
            )
        )

        #expect(loaded.map(\.name) == ["Sources", "Tests", "main.swift"])
    }

    @Test
    func writeFileEncodesContentAsBase64() async throws {
        let service = RecordingWriteService()
        let useCase = SessionFileWriteUseCase(service: service)

        _ = try await useCase.writeFile(
            SessionFileWriteRequest(
                serverURLString: "https://api.unhappy.im",
                token: "token",
                sessionID: "session-1",
                path: "/repo/file.txt",
                content: "hello",
                expectedHash: "hash-1"
            )
        )

        let recorded = await service.lastContent()
        let decoded = Data(base64Encoded: recorded ?? "") ?? Data()
        #expect(String(decoding: decoded, as: UTF8.self) == "hello")
    }

    @Test
    func writeFileThrowsWhenContentIsEmpty() async {
        let useCase = SessionFileWriteUseCase(service: RecordingWriteService())

        await #expect(throws: SessionFileCommandError.missingContent) {
            _ = try await useCase.writeFile(
                SessionFileWriteRequest(
                    serverURLString: "https://api.unhappy.im",
                    token: "token",
                    sessionID: "session-1",
                    path: "/repo/file.txt",
                    content: "",
                    expectedHash: nil
                )
            )
        }
    }

    @Test
    func loadFileDiffBuildsGitDiffCommand() async throws {
        let basher = RecordingBashAction(
            result: .init(success: true, stdout: "diff", stderr: "", exitCode: 0, error: nil)
        )
        let useCase = SessionFileDiffPreviewUseCase(basher: basher)

        _ = try await useCase.loadFileDiff(
            SessionFileDiffPreviewRequest(
                serverURLString: "https://api.unhappy.im",
                token: "token",
                sessionID: "session-1",
                path: "/repo/Sources/App.swift",
                workingDirectory: nil,
                timeout: 12_000
            )
        )

        let request = await basher.lastRequest()
        #expect(request?.sessionID == "session-1")
        #expect(request?.command == "git -C '/repo/Sources' diff --no-ext-diff -- '/repo/Sources/App.swift'")
        #expect(request?.timeout == 12_000)
    }

    @Test
    func loadFileDiffThrowsWhenPathMissing() async {
        let useCase = SessionFileDiffPreviewUseCase(
            basher: RecordingBashAction(
                result: .init(success: true, stdout: "", stderr: "", exitCode: 0, error: nil)
            )
        )

        await #expect(throws: SessionFileCommandError.missingPath) {
            _ = try await useCase.loadFileDiff(
                SessionFileDiffPreviewRequest(
                    serverURLString: "https://api.unhappy.im",
                    token: "token",
                    sessionID: "session-1",
                    path: " ",
                    workingDirectory: nil,
                    timeout: nil
                )
            )
        }
    }
}

private struct DirectoryService: SessionDirectoryListing {
    let result: APISessionListDirectoryResult

    func listDirectory(
        serverURL: URL,
        token: String,
        sessionID: String,
        path: String
    ) async throws -> APISessionListDirectoryResult {
        result
    }
}

private actor RecordingWriteService: SessionFileWriting {
    private var recordedContent: String?

    func writeFile(
        serverURL: URL,
        token: String,
        sessionID: String,
        path: String,
        content: String,
        expectedHash: String?
    ) async throws -> APISessionWriteFileResult {
        recordedContent = content
        return .init(success: true, hash: "next-hash", error: nil)
    }

    func lastContent() -> String? { recordedContent }
}

private struct BashRequest: Equatable {
    let serverURLString: String
    let token: String
    let sessionID: String
    let command: String
    let cwd: String?
    let timeout: Int?
}

private actor RecordingBashAction: SessionBashRunAction {
    let result: APISessionBashResult
    private var request: BashRequest?

    init(result: APISessionBashResult) {
        self.result = result
    }

    func runBash(_ bashRequest: SessionBashCommandRequest) async throws -> APISessionBashResult {
        request = BashRequest(
            serverURLString: bashRequest.serverURLString,
            token: bashRequest.token,
            sessionID: bashRequest.sessionID,
            command: bashRequest.command,
            cwd: bashRequest.cwd,
            timeout: bashRequest.timeout
        )
        return result
    }

    func lastRequest() -> BashRequest? { request }
}
