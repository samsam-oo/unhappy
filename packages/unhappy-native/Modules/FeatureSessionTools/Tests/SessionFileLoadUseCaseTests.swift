import Foundation
import Testing
@testable import FeatureSessionTools
import CoreKit

struct SessionFileLoadUseCaseTests {
    @Test
    func loadFileThrowsMissingToken() async {
        let useCase = SessionFileLoadUseCase(service: ImmediateReadFileService(result: .init(success: true, content: nil, error: nil)))

        await #expect(throws: SessionFileLoadError.missingToken) {
            _ = try await useCase.loadFile(
                serverURLString: "https://api.unhappy.im",
                token: " ",
                sessionID: "session-1",
                path: "/tmp/file.txt"
            )
        }
    }

    @Test
    func loadFileDecodesBase64Text() async throws {
        let content = Data("hello world".utf8).base64EncodedString()
        let service = ImmediateReadFileService(
            result: APISessionReadFileResult(success: true, content: content, error: nil)
        )
        let useCase = SessionFileLoadUseCase(service: service)

        let loaded = try await useCase.loadFile(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            sessionID: "session-1",
            path: "/tmp/file.txt"
        )

        #expect(loaded == "hello world")
    }

    @Test
    func loadFileThrowsInvalidBase64() async {
        let service = ImmediateReadFileService(
            result: APISessionReadFileResult(success: true, content: "!!!", error: nil)
        )
        let useCase = SessionFileLoadUseCase(service: service)

        await #expect(throws: SessionFileLoadError.invalidBase64Content) {
            _ = try await useCase.loadFile(
                serverURLString: "https://api.unhappy.im",
                token: "token",
                sessionID: "session-1",
                path: "/tmp/file.txt"
            )
        }
    }

    @Test
    func concurrentLoadsShareSingleInFlightRequest() async throws {
        let content = Data("shared".utf8).base64EncodedString()
        let service = SlowCountingReadFileService(
            result: APISessionReadFileResult(success: true, content: content, error: nil)
        )
        let useCase = SessionFileLoadUseCase(service: service)

        async let first = useCase.loadFile(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            sessionID: "session-1",
            path: "/tmp/file.txt"
        )
        async let second = useCase.loadFile(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            sessionID: "session-1",
            path: "/tmp/file.txt"
        )

        let firstResult = try await first
        let secondResult = try await second

        #expect(firstResult == secondResult)
        #expect(await service.fetchCount() == 1)
    }
}

private struct ImmediateReadFileService: SessionFileReading {
    let result: APISessionReadFileResult

    func readFile(serverURL: URL, token: String, sessionID: String, path: String) async throws -> APISessionReadFileResult {
        result
    }
}

private actor SlowCountingReadFileService: SessionFileReading {
    private let result: APISessionReadFileResult
    private var count: Int = 0

    init(result: APISessionReadFileResult) {
        self.result = result
    }

    func readFile(serverURL: URL, token: String, sessionID: String, path: String) async throws -> APISessionReadFileResult {
        count += 1
        try await Task.sleep(nanoseconds: 80_000_000)
        return result
    }

    func fetchCount() -> Int {
        count
    }
}
