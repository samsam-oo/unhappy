import SwiftUI

@MainActor
public struct InboxView: View {
    @StateObject private var viewModel: InboxViewModel
    private let serverURLString: String
    private let token: String

    public init(
        serverURLString: String,
        token: String,
        makeViewModel: @escaping @MainActor () -> InboxViewModel
    ) {
        self.serverURLString = serverURLString
        self.token = token
        _viewModel = StateObject(wrappedValue: makeViewModel())
    }

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading inbox…")
                } else if let errorMessage = viewModel.errorMessage {
                    ContentUnavailableView(
                        "Unable to load inbox",
                        systemImage: "tray.full",
                        description: Text(errorMessage)
                    )
                } else if viewModel.isEmpty {
                    ContentUnavailableView(
                        "No inbox items",
                        systemImage: "tray",
                        description: Text("Notifications and pending requests will appear here.")
                    )
                } else {
                    inboxListContent
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await viewModel.load()
                    }
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        InboxFriendsView(viewModel: viewModel)
                    } label: {
                        Image(systemName: "person.2")
                    }
                    .accessibilityLabel("Open friends")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        InboxFriendSearchView(viewModel: viewModel)
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .accessibilityLabel("Search users")
                }
            }
            .task(id: "\(serverURLString)|\(token)") {
                viewModel.updateConfiguration(
                    serverURLString: serverURLString,
                    token: token
                )
                await viewModel.load()
            }
        }
    }

    private var inboxListContent: some View {
        List {
            updatesSection
            pendingRequestsSection
            sentRequestsSection
            friendsSection
        }
    }

    @ViewBuilder
    private var updatesSection: some View {
        if !viewModel.feedItems.isEmpty {
            Section("Updates") {
                ForEach(viewModel.feedItems) { item in
                    if let userID = item.relatedUserID {
                        NavigationLink {
                            InboxUserProfileView(userID: userID, viewModel: viewModel)
                        } label: {
                            feedRow(item: item)
                        }
                    } else {
                        feedRow(item: item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var pendingRequestsSection: some View {
        if !viewModel.friendRequests.isEmpty {
            Section("Pending Requests") {
                ForEach(viewModel.friendRequests) { friend in
                    NavigationLink {
                        InboxUserProfileView(userID: friend.id, viewModel: viewModel)
                    } label: {
                        friendRow(friend: friend)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Reject", role: .destructive) {
                            Task { await viewModel.rejectFriendRequest(userID: friend.id) }
                        }
                        .disabled(viewModel.isApplyingFriendAction)

                        Button("Accept") {
                            Task { await viewModel.acceptFriendRequest(userID: friend.id) }
                        }
                        .tint(.green)
                        .disabled(viewModel.isApplyingFriendAction)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sentRequestsSection: some View {
        if !viewModel.requestedFriends.isEmpty {
            Section("Sent Requests") {
                ForEach(viewModel.requestedFriends) { friend in
                    NavigationLink {
                        InboxUserProfileView(userID: friend.id, viewModel: viewModel)
                    } label: {
                        friendRow(friend: friend)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Cancel", role: .destructive) {
                            Task { await viewModel.cancelFriendRequest(userID: friend.id) }
                        }
                        .disabled(viewModel.isApplyingFriendAction)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var friendsSection: some View {
        if !viewModel.friends.isEmpty {
            Section("Friends") {
                ForEach(viewModel.friends) { friend in
                    NavigationLink {
                        InboxUserProfileView(userID: friend.id, viewModel: viewModel)
                    } label: {
                        friendRow(friend: friend)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Remove", role: .destructive) {
                            Task { await viewModel.removeFriend(userID: friend.id) }
                        }
                        .disabled(viewModel.isApplyingFriendAction)
                    }
                }
            }
        }
    }

    private func feedRow(item: InboxItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.headline)
            Text(item.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(item.timestamp, style: .relative)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func friendRow(friend: InboxFriend) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(friend.displayName)
                .font(.headline)
            Text(friend.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    InboxView(
        serverURLString: "https://api.unhappy.im",
        token: "preview-token"
    ) {
        InboxViewModel(loader: PreviewInboxLoader())
    }
}

private actor PreviewInboxLoader: InboxLoadingAction {
    func loadInboxSnapshot(serverURLString: String, token: String) async throws -> InboxSnapshot {
        InboxSnapshot(
            feedItems: [
                InboxItem(
                    id: "feed-1",
                    title: "Daemon updated",
                    subtitle: "Machine mac-mini-01 is now on the latest daemon build.",
                    timestamp: Date().addingTimeInterval(-3600)
                )
            ],
            friendRequests: [
                InboxFriend(id: "u1", displayName: "Skyline", subtitle: "@skyline23")
            ],
            requestedFriends: [],
            friends: [
                InboxFriend(id: "u2", displayName: "Alex", subtitle: "@alex")
            ]
        )
    }
}
