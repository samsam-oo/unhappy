import SwiftUI

@MainActor
public struct InboxUserProfileView: View {
    let userID: String
    @ObservedObject var viewModel: InboxViewModel

    @State private var isLoading = false
    @State private var isPerformingAction = false
    @State private var profile: InboxUserProfile?
    @State private var errorMessage: String?

    public init(userID: String, viewModel: InboxViewModel) {
        self.userID = userID
        self.viewModel = viewModel
    }

    public var body: some View {
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
        .navigationBarTitleDisplayMode(.inline)
        .task(id: userID) {
            await refresh()
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
