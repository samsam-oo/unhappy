import SwiftUI

@MainActor
public struct InboxView: View {
    @StateObject private var viewModel: InboxViewModel
    @State private var isSearchPresented = false
    @State private var selectedUser: SelectedInboxUser?
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
                                    if let userID = item.relatedUserID {
                                        Button {
                                            selectedUser = SelectedInboxUser(id: userID)
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
                                        selectedUser = SelectedInboxUser(id: friend.id)
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
                                        selectedUser = SelectedInboxUser(id: friend.id)
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
                                        selectedUser = SelectedInboxUser(id: friend.id)
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
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSearchPresented = true
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
        .sheet(isPresented: $isSearchPresented) {
            InboxFriendSearchSheet(viewModel: viewModel)
        }
        .sheet(item: $selectedUser) { selected in
            InboxUserProfileSheet(userID: selected.id, viewModel: viewModel)
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

private struct SelectedInboxUser: Identifiable {
    let id: String
}

@MainActor
private struct InboxUserProfileSheet: View {
    let userID: String
    @ObservedObject var viewModel: InboxViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var isPerformingAction = false
    @State private var profile: InboxUserProfile?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading user…")
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Unable to load profile",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text(errorMessage)
                    )
                } else if let profile {
                    List {
                        Section("Profile") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(profile.displayName)
                                    .font(.title3.weight(.semibold))
                                Text("@\(profile.username)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if let bio = profile.bio, !bio.isEmpty {
                                    Text(bio)
                                        .font(.body)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        Section("Status") {
                            Text(statusText(profile.status))
                                .foregroundStyle(.secondary)
                        }

                        Section("Actions") {
                            actionButtons(for: profile)
                        }
                    }
                    .listStyle(.insetGrouped)
                } else {
                    ContentUnavailableView(
                        "User not found",
                        systemImage: "person.slash",
                        description: Text("This profile is no longer available.")
                    )
                }
            }
            .navigationTitle("User")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: userID) {
                await refresh()
            }
        }
    }

    @ViewBuilder
    private func actionButtons(for profile: InboxUserProfile) -> some View {
        switch profile.status {
        case .pending:
            Button("Accept") {
                Task { await performAction { await viewModel.acceptFriendRequest(userID: profile.id) } }
            }
            .disabled(isPerformingAction)
            Button("Reject", role: .destructive) {
                Task { await performAction { await viewModel.rejectFriendRequest(userID: profile.id) } }
            }
            .disabled(isPerformingAction)
        case .requested:
            Button("Cancel Request", role: .destructive) {
                Task { await performAction { await viewModel.cancelFriendRequest(userID: profile.id) } }
            }
            .disabled(isPerformingAction)
        case .friend:
            Button("Remove Friend", role: .destructive) {
                Task { await performAction { await viewModel.removeFriend(userID: profile.id) } }
            }
            .disabled(isPerformingAction)
        case .none, .rejected:
            Button("Add Friend") {
                Task { await performAction { await viewModel.sendFriendRequest(userID: profile.id) } }
            }
            .disabled(isPerformingAction)
        }
    }

    private func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            profile = try await viewModel.loadUserProfile(userID: userID)
            errorMessage = nil
        } catch {
            profile = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func performAction(_ action: @escaping () async -> Void) async {
        isPerformingAction = true
        defer { isPerformingAction = false }
        await action()
        await refresh()
    }

    private func statusText(_ status: InboxUserRelationshipStatus) -> String {
        switch status {
        case .none:
            return "Not connected"
        case .requested:
            return "Friend request sent"
        case .pending:
            return "Requested you"
        case .friend:
            return "Friend"
        case .rejected:
            return "Previously removed"
        }
    }
}

@MainActor
private struct InboxFriendSearchSheet: View {
    @ObservedObject var viewModel: InboxViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [InboxUserProfile] = []
    @State private var isSearching = false
    @State private var isPerformingAction = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Search") {
                    HStack {
                        TextField("username", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit {
                                Task { await search() }
                            }
                        Button("Search") {
                            Task { await search() }
                        }
                        .disabled(isSearching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if isSearching {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                if !results.isEmpty {
                    Section("Results") {
                        ForEach(results) { profile in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.displayName)
                                        .font(.headline)
                                    Text("@\(profile.username)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                actionButton(for: profile)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Find Friends")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func actionButton(for profile: InboxUserProfile) -> some View {
        switch profile.status {
        case .none, .rejected:
            Button("Add") {
                Task { await performAction { await viewModel.sendFriendRequest(userID: profile.id) } }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPerformingAction)
        case .requested:
            Button("Cancel") {
                Task { await performAction { await viewModel.cancelFriendRequest(userID: profile.id) } }
            }
            .buttonStyle(.bordered)
            .disabled(isPerformingAction)
        case .pending:
            Button("Accept") {
                Task { await performAction { await viewModel.acceptFriendRequest(userID: profile.id) } }
            }
            .buttonStyle(.bordered)
            .disabled(isPerformingAction)
        case .friend:
            Text("Friend")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func search() async {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            results = []
            errorMessage = nil
            return
        }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            results = try await viewModel.searchUsers(query: normalized)
        } catch {
            results = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func performAction(_ action: @escaping () async -> Void) async {
        isPerformingAction = true
        defer { isPerformingAction = false }
        await action()
        await search()
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
