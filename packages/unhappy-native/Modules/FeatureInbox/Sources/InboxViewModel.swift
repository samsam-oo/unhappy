import Foundation

@MainActor
public final class InboxViewModel: ObservableObject {
    @Published public private(set) var feedItems: [InboxItem] = []
    @Published public private(set) var friendRequests: [InboxFriend] = []
    @Published public private(set) var requestedFriends: [InboxFriend] = []
    @Published public private(set) var friends: [InboxFriend] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var isApplyingFriendAction = false
    @Published public private(set) var errorMessage: String?

    private let loader: any InboxLoadingAction
    private let friendAction: any InboxFriendActionPerforming
    private let userProfileLoader: any InboxUserProfileLoadingAction
    private let userSearcher: any InboxUserSearchingAction
    private var serverURLString: String
    private var token: String

    public init(
        loader: any InboxLoadingAction,
        friendAction: any InboxFriendActionPerforming = InboxNoopFriendActionUseCase(),
        userProfileLoader: any InboxUserProfileLoadingAction = InboxNoopUserProfileLoader(),
        userSearcher: any InboxUserSearchingAction = InboxNoopUserSearcher(),
        serverURLString: String = "",
        token: String = ""
    ) {
        self.loader = loader
        self.friendAction = friendAction
        self.userProfileLoader = userProfileLoader
        self.userSearcher = userSearcher
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

    public func acceptFriendRequest(userID: String) async {
        await performFriendAction {
            try await friendAction.acceptFriendRequest(
                serverURLString: serverURLString,
                token: token,
                userID: userID
            )
        }
    }

    public func rejectFriendRequest(userID: String) async {
        await performFriendAction {
            try await friendAction.rejectFriendRequest(
                serverURLString: serverURLString,
                token: token,
                userID: userID
            )
        }
    }

    public func cancelFriendRequest(userID: String) async {
        await performFriendAction {
            try await friendAction.cancelFriendRequest(
                serverURLString: serverURLString,
                token: token,
                userID: userID
            )
        }
    }

    public func removeFriend(userID: String) async {
        await performFriendAction {
            try await friendAction.removeFriend(
                serverURLString: serverURLString,
                token: token,
                userID: userID
            )
        }
    }

    public func sendFriendRequest(userID: String) async {
        await performFriendAction {
            try await friendAction.acceptFriendRequest(
                serverURLString: serverURLString,
                token: token,
                userID: userID
            )
        }
    }

    public func loadUserProfile(userID: String) async throws -> InboxUserProfile? {
        try await userProfileLoader.loadUserProfile(
            serverURLString: serverURLString,
            token: token,
            userID: userID
        )
    }

    public func searchUsers(query: String) async throws -> [InboxUserProfile] {
        try await userSearcher.searchUsers(
            serverURLString: serverURLString,
            token: token,
            query: query
        )
    }

    private func performFriendAction(_ action: () async throws -> Void) async {
        isApplyingFriendAction = true
        defer { isApplyingFriendAction = false }

        do {
            try await action()
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
