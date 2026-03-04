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
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
                .navigationTitle("Inbox")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { inboxToolbarContent }
                .refreshable {
                    await viewModel.load()
                }
        } detail: {
            splitDetailPlaceholder
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(detailCanvasColor)
        }
        .navigationSplitViewStyle(.balanced)
        .task(id: "\(serverURLString)|\(token)") {
            viewModel.updateConfiguration(
                serverURLString: serverURLString,
                token: token
            )
            await viewModel.load()
        }
    }

    @ViewBuilder
    private var sidebarContent: some View {
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
                emptySidebarState
            } else {
                inboxListContent
                    .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(sidebarCanvasColor)
    }

    @ViewBuilder
    private var splitDetailPlaceholder: some View {
        if viewModel.isLoading {
            ProgressView("Loading inbox…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.isEmpty {
            emptyDetailState
        } else {
            chooseItemDetailState
        }
    }

    private var emptySidebarState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("No inbox items")
                .font(.subheadline.weight(.semibold))
            Text("Notifications and requests will appear here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyDetailState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray.full")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Inbox is empty")
                .font(.title3.weight(.semibold))
            Text("Friend requests and updates will show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
    }

    private var chooseItemDetailState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Select an Inbox Item")
                .font(.headline)
            Text("Choose an item from the left panel to open details.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
    }

    private var inboxListContent: some View {
        List {
            updatesSection
            pendingRequestsSection
            sentRequestsSection
            friendsSection
        }
        .scrollContentBackground(.hidden)
        .background(sidebarCanvasColor)
    }

    @ToolbarContentBuilder
    private var inboxToolbarContent: some ToolbarContent {
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

    private var sidebarCanvasColor: Color {
        Color(uiColor: .systemBackground)
    }

    private var detailCanvasColor: Color {
        Color(uiColor: .systemGroupedBackground)
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
