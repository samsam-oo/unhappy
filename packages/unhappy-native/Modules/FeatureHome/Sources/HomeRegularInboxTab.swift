import SwiftUI
import FeatureInbox

private enum HomeRegularInboxSelection: Hashable {
    case friends
    case search
    case user(String)
}

@MainActor
struct HomeRegularInboxTab: View {
    @ObservedObject var viewModel: InboxViewModel
    let serverURLString: String
    let token: String

    @State private var selection: HomeRegularInboxSelection?

    var body: some View {
        HStack(spacing: 0) {
            sidebarNavigation
                .frame(width: 340)
            Divider()
            detail
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task(id: "\(serverURLString)|\(token)") {
            viewModel.updateConfiguration(serverURLString: serverURLString, token: token)
            await viewModel.load()
        }
    }

    private var sidebarNavigation: some View {
        NavigationStack {
            sidebar
                .navigationTitle("Inbox")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { inboxSidebarToolbar }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading inbox…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView(
                    "Unable to load inbox",
                    systemImage: "tray.full",
                    description: Text(errorMessage)
                )
            } else if viewModel.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("No inbox items")
                        .font(.subheadline.weight(.semibold))
                    Text("Notifications and requests will appear here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 16)
                .padding(.top, 10)
            } else {
                list
            }
        }
        .contentMargins(.top, 8, for: .scrollContent)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .systemBackground))
    }

    @ToolbarContentBuilder
    private var inboxSidebarToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                selection = .friends
            } label: {
                Image(systemName: "person.2")
            }
            .accessibilityLabel("Open friends")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                selection = .search
            } label: {
                Image(systemName: "person.badge.plus")
            }
            .accessibilityLabel("Search users")
        }
    }

    private var list: some View {
        List {
            if !viewModel.feedItems.isEmpty {
                Section("Updates") {
                    ForEach(viewModel.feedItems) { item in
                        if let userID = item.relatedUserID {
                            Button {
                                selection = .user(userID)
                            } label: {
                                feedRow(item: item)
                            }
                            .buttonStyle(.plain)
                        } else {
                            feedRow(item: item)
                        }
                    }
                }
            }

            if !viewModel.friendRequests.isEmpty {
                Section("Pending Requests") {
                    ForEach(viewModel.friendRequests) { friend in
                        Button {
                            selection = .user(friend.id)
                        } label: {
                            friendRow(friend: friend)
                        }
                        .buttonStyle(.plain)
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
                        Button {
                            selection = .user(friend.id)
                        } label: {
                            friendRow(friend: friend)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Cancel", role: .destructive) {
                                Task { await viewModel.cancelFriendRequest(userID: friend.id) }
                            }
                            .disabled(viewModel.isApplyingFriendAction)
                        }
                    }
                }
            }

            if !viewModel.friends.isEmpty {
                Section("Friends") {
                    ForEach(viewModel.friends) { friend in
                        Button {
                            selection = .user(friend.id)
                        } label: {
                            friendRow(friend: friend)
                        }
                        .buttonStyle(.plain)
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
        .listStyle(.plain)
        .contentMargins(.top, 8, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemBackground))
    }

    private var detail: some View {
        NavigationStack {
            switch selection {
            case .friends:
                InboxFriendsView(viewModel: viewModel)
            case .search:
                InboxFriendSearchView(viewModel: viewModel)
            case .user(let userID):
                InboxUserProfileView(userID: userID, viewModel: viewModel)
            case .none:
                VStack(spacing: 10) {
                    Image(systemName: viewModel.isEmpty ? "tray.full" : "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(viewModel.isEmpty ? "Inbox is empty" : "Select an Inbox Item")
                        .font(.headline)
                    Text(
                        viewModel.isEmpty
                            ? "Friend requests and updates will show up here."
                            : "Choose an item from the left panel to open details."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemGroupedBackground))
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
