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
            serverURLString: "https://api.unhappy.im",
            token: "token",
            sessionID: "session-1",
            path: "/repo"
        )

        #expect(loaded.map(\.name) == ["Sources", "Tests", "main.swift"])
    }

    @Test
    func writeFileEncodesContentAsBase64() async throws {
        let service = RecordingWriteService()
        let useCase = SessionFileWriteUseCase(service: service)

        _ = try await useCase.writeFile(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            sessionID: "session-1",
            path: "/repo/file.txt",
            content: "hello",
            expectedHash: "hash-1"
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
                serverURLString: "https://api.unhappy.im",
                token: "token",
                sessionID: "session-1",
                path: "/repo/file.txt",
                content: "",
                expectedHash: nil
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
