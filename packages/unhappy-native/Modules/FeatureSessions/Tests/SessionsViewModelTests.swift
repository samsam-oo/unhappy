import Foundation
import Testing
@testable import FeatureSessions
import CoreKit

struct SessionsViewModelTests {
    @Test
    func loadSuccessPublishesSessions() async throws {
        let expected = [
            APISession(
                id: "s1",
                active: true,
                activeAt: 10,
                createdAt: 1,
                updatedAt: 11,
                metadataVersion: 2,
                metadata: "enc",
                dataEncryptionKey: nil,
                lastMessage: nil
            )
        ]
        let service = MockSessionsService(result: .success(expected))
        let model = SessionsViewModel(service: service)

        await model.load(
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        #expect(model.sessions.count == 1)
        #expect(model.errorMessage == nil)
    }

    @Test
    func loadWithoutTokenSetsValidationError() async throws {
        let service = MockSessionsService(result: .success([]))
        let model = SessionsViewModel(service: service)

        await model.load(serverURLString: "https://api.unhappy.im", token: "")

        #expect(model.sessions.isEmpty)
        #expect(model.errorMessage == "API token is required")
    }
}

private struct MockSessionsService: SessionsFetching {
    let result: Result<[APISession], Error>

    func fetchSessions(serverURL: URL, token: String) async throws -> [APISession] {
        switch result {
        case .success(let sessions):
            return sessions
        case .failure(let error):
            throw error
        }
    }
}
