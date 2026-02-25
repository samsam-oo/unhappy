import Foundation

@MainActor
public final class InboxViewModel: ObservableObject {
    @Published public private(set) var feedItems: [InboxItem] = []
    @Published public private(set) var friendRequests: [InboxFriend] = []
    @Published public private(set) var requestedFriends: [InboxFriend] = []
    @Published public private(set) var friends: [InboxFriend] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?

    private let loader: any InboxLoadingAction
    private var serverURLString: String
    private var token: String

    public init(
        loader: any InboxLoadingAction,
        serverURLString: String = "",
        token: String = ""
    ) {
        self.loader = loader
        self.serverURLString = serverURLString
        self.token = token
    }

    public var isEmpty: Bool {
        feedItems.isEmpty
        && friendRequests.isEmpty
        && requestedFriends.isEmpty
        && friends.isEmpty
    }

    public func updateConfiguration(serverURLString: String, token: String) {
        self.serverURLString = serverURLString
        self.token = token
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let snapshot = try await loader.loadInboxSnapshot(
                serverURLString: serverURLString,
                token: token
            )
            feedItems = snapshot.feedItems
            friendRequests = snapshot.friendRequests
            requestedFriends = snapshot.requestedFriends
            friends = snapshot.friends
            errorMessage = nil
        } catch {
            feedItems = []
            friendRequests = []
            requestedFriends = []
            friends = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
