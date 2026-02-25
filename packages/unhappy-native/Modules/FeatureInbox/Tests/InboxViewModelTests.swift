import Foundation
import Testing
@testable import FeatureInbox

@MainActor
struct InboxViewModelTests {
    @Test
    func loadPublishesSnapshot() async {
        let loader = MockInboxLoader(
            result: .success(
                InboxSnapshot(
                    feedItems: [
                        InboxItem(
                            id: "inbox-1",
                            title: "Title",
                            subtitle: "Subtitle",
                            timestamp: Date()
                        )
                    ],
                    friendRequests: [
                        InboxFriend(id: "u1", displayName: "Alpha", subtitle: "@alpha")
                    ],
                    requestedFriends: [],
                    friends: []
                )
            )
        )
        let viewModel = InboxViewModel(loader: loader)
        viewModel.updateConfiguration(
            serverURLString: "https://api.unhappy.im",
            token: "token-1"
        )

        await viewModel.load()

        #expect(viewModel.feedItems.count == 1)
        #expect(viewModel.friendRequests.count == 1)
        #expect(viewModel.requestedFriends.isEmpty)
        #expect(viewModel.friends.isEmpty)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isLoading == false)
        let call = await loader.firstCall()
        #expect(call?.serverURLString == "https://api.unhappy.im")
        #expect(call?.token == "token-1")
    }

    @Test
    func loadPublishesError() async {
        let viewModel = InboxViewModel(
            loader: MockInboxLoader(result: .failure(InboxTestError.failed)),
            serverURLString: "https://api.unhappy.im",
            token: "token"
        )

        await viewModel.load()

        #expect(viewModel.feedItems.isEmpty)
        #expect(viewModel.friendRequests.isEmpty)
        #expect(viewModel.requestedFriends.isEmpty)
        #expect(viewModel.friends.isEmpty)
        #expect(viewModel.errorMessage == "failed")
        #expect(viewModel.isLoading == false)
    }
}

private enum InboxTestError: LocalizedError {
    case failed

    var errorDescription: String? { "failed" }
}

private actor MockInboxLoader: InboxLoadingAction {
    private let result: Result<InboxSnapshot, Error>
    private var calls: [(serverURLString: String, token: String)] = []

    init(result: Result<InboxSnapshot, Error>) {
        self.result = result
    }

    func loadInboxSnapshot(serverURLString: String, token: String) async throws -> InboxSnapshot {
        calls.append((serverURLString: serverURLString, token: token))
        return try result.get()
    }

    func firstCall() -> (serverURLString: String, token: String)? {
        calls.first
    }
}
