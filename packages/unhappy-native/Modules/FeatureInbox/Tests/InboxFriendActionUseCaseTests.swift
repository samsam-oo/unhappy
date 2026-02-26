import Foundation
import Testing
@testable import FeatureInbox
import CoreKit

struct InboxFriendActionUseCaseTests {
    @Test
    func acceptThrowsMissingToken() async {
        let useCase = InboxFriendActionUseCase(
            adder: MockFriendAdder(),
            remover: MockFriendRemover()
        )

        await #expect(throws: InboxFriendActionError.missingToken) {
            try await useCase.acceptFriendRequest(
                serverURLString: "https://api.unhappy.im",
                token: " ",
                userID: "user-1"
            )
        }
    }

    @Test
    func removeThrowsInvalidServerURL() async {
        let useCase = InboxFriendActionUseCase(
            adder: MockFriendAdder(),
            remover: MockFriendRemover()
        )

        await #expect(throws: InboxFriendActionError.invalidServerURL) {
            try await useCase.removeFriend(
                serverURLString: "invalid-url",
                token: "token",
                userID: "user-1"
            )
        }
    }

    @Test
    func rejectThrowsMissingUserID() async {
        let useCase = InboxFriendActionUseCase(
            adder: MockFriendAdder(),
            remover: MockFriendRemover()
        )

        await #expect(throws: InboxFriendActionError.missingUserID) {
            try await useCase.rejectFriendRequest(
                serverURLString: "https://api.unhappy.im",
                token: "token",
                userID: " "
            )
        }
    }

    @Test
    func acceptCallsAddFriendWithNormalizedInputs() async throws {
        let adder = MockFriendAdder()
        let useCase = InboxFriendActionUseCase(
            adder: adder,
            remover: MockFriendRemover()
        )

        try await useCase.acceptFriendRequest(
            serverURLString: " https://api.unhappy.im ",
            token: " token-1 ",
            userID: " user-1 "
        )

        let call = await adder.lastCall()
        #expect(call?.serverURL.absoluteString == "https://api.unhappy.im")
        #expect(call?.token == "token-1")
        #expect(call?.userID == "user-1")
    }

    @Test
    func rejectAndCancelUseRemoveFriend() async throws {
        let remover = MockFriendRemover()
        let useCase = InboxFriendActionUseCase(
            adder: MockFriendAdder(),
            remover: remover
        )

        try await useCase.rejectFriendRequest(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            userID: "user-1"
        )
        try await useCase.cancelFriendRequest(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            userID: "user-2"
        )

        #expect(await remover.callCount() == 2)
    }
}

private actor MockFriendAdder: FriendAdding {
    private var calls: [(serverURL: URL, token: String, userID: String)] = []

    func addFriend(serverURL: URL, token: String, userID: String) async throws -> APIUserProfile? {
        calls.append((serverURL: serverURL, token: token, userID: userID))
        return nil
    }

    func lastCall() -> (serverURL: URL, token: String, userID: String)? {
        calls.last
    }
}

private actor MockFriendRemover: FriendRemoving {
    private var calls: [(serverURL: URL, token: String, userID: String)] = []

    func removeFriend(serverURL: URL, token: String, userID: String) async throws -> APIUserProfile? {
        calls.append((serverURL: serverURL, token: token, userID: userID))
        return nil
    }

    func callCount() -> Int {
        calls.count
    }
}
