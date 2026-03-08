import SwiftUI

@MainActor
public struct InboxFriendSearchView: View {
    @ObservedObject var viewModel: InboxViewModel

    @State private var query = ""
    @State private var results: [InboxUserProfile] = []
    @State private var isSearching = false
    @State private var isPerformingAction = false
    @State private var hasSearched = false
    @State private var errorMessage: String?

    public init(viewModel: InboxViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
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
                            NavigationLink {
                                InboxUserProfileView(userID: profile.id, viewModel: viewModel)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.displayName)
                                        .font(.headline)
                                    Text("@\(profile.username)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            actionButton(for: profile)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if hasSearched && !isSearching && errorMessage == nil && results.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No users found",
                        systemImage: "person.crop.circle.badge.xmark",
                        description: Text("Try a different username prefix.")
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Find Friends")
        .navigationBarTitleDisplayMode(.inline)
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
            hasSearched = false
            return
        }

        isSearching = true
        errorMessage = nil
        hasSearched = true
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
