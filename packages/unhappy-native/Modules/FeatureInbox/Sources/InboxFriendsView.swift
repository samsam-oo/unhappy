import SwiftUI

@MainActor
public struct InboxFriendsView: View {
    @ObservedObject var viewModel: InboxViewModel

    public init(viewModel: InboxViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        content
        .navigationTitle("Friends")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    InboxFriendSearchView(viewModel: viewModel)
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .accessibilityLabel("Search users")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isEmptyState {
            ContentUnavailableView(
                "No friends yet",
                systemImage: "person.2.slash",
                description: Text("Use Find Friends to send your first request.")
            )
        } else {
            List {
                pendingRequestsSection
                sentRequestsSection
                friendsSection
            }
            .listStyle(.insetGrouped)
            .refreshable { await viewModel.load() }
        }
    }

    private var isEmptyState: Bool {
        viewModel.friendRequests.isEmpty
            && viewModel.requestedFriends.isEmpty
            && viewModel.friends.isEmpty
    }

    @ViewBuilder
    private var pendingRequestsSection: some View {
        if !viewModel.friendRequests.isEmpty {
            Section("Pending Requests") {
                ForEach(viewModel.friendRequests) { friend in
                    NavigationLink {
                        InboxUserProfileView(userID: friend.id, viewModel: viewModel)
                    } label: {
                        friendRow(friend)
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
                        friendRow(friend)
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

    private var friendsSection: some View {
        Section("Friends") {
            if viewModel.friends.isEmpty {
                Text("No accepted friends yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.friends) { friend in
                    NavigationLink {
                        InboxUserProfileView(userID: friend.id, viewModel: viewModel)
                    } label: {
                        friendRow(friend)
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

    private func friendRow(_ friend: InboxFriend) -> some View {
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
