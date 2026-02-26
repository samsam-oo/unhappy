import SwiftUI

@MainActor
struct InboxFriendsView: View {
    @ObservedObject var viewModel: InboxViewModel

    var body: some View {
        List {
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

            Section("Friends") {
                if viewModel.friends.isEmpty {
                    Text("No friends yet")
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
        .listStyle(.insetGrouped)
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
