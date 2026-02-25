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
                    List {
                        if !viewModel.feedItems.isEmpty {
                            Section("Updates") {
                                ForEach(viewModel.feedItems) { item in
                                    feedRow(item: item)
                                }
                            }
                        }

                        if !viewModel.friendRequests.isEmpty {
                            Section("Pending Requests") {
                                ForEach(viewModel.friendRequests) { friend in
                                    friendRow(friend: friend)
                                }
                            }
                        }

                        if !viewModel.requestedFriends.isEmpty {
                            Section("Sent Requests") {
                                ForEach(viewModel.requestedFriends) { friend in
                                    friendRow(friend: friend)
                                }
                            }
                        }

                        if !viewModel.friends.isEmpty {
                            Section("Friends") {
                                ForEach(viewModel.friends) { friend in
                                    friendRow(friend: friend)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Inbox")
            .task(id: "\(serverURLString)|\(token)") {
                viewModel.updateConfiguration(
                    serverURLString: serverURLString,
                    token: token
                )
                await viewModel.load()
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
