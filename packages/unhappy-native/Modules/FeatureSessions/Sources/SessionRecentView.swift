import SwiftUI
import CoreKit

@MainActor
public struct SessionRecentView: View {
    @ObservedObject var viewModel: SessionsViewModel
    let serverURLString: String
    let token: String
    let makeDirectSessionViewModel: @MainActor (DirectSessionIdentity) -> DirectSessionViewModel
    @State private var archiveErrorMessage: String?

    public init(
        viewModel: SessionsViewModel,
        serverURLString: String,
        token: String,
        makeDirectSessionViewModel: @escaping @MainActor (DirectSessionIdentity) -> DirectSessionViewModel
    ) {
        self.viewModel = viewModel
        self.serverURLString = serverURLString
        self.token = token
        self.makeDirectSessionViewModel = makeDirectSessionViewModel
    }

    public var body: some View {
        let sections = SessionRecentPresentationBuilder.make(
            upstreamSessions: viewModel.upstreamSessions
        )

        List {
            if sections.isEmpty {
                Text("No recent sessions")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.entries) { entry in
                            recentNavigationLink(for: entry)
                        }
                    }
                }
            }
        }
        .navigationTitle("Recent Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Couldn't Archive Session",
            isPresented: Binding(
                get: { archiveErrorMessage?.isEmpty == false },
                set: { isPresented in
                    if !isPresented {
                        archiveErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                archiveErrorMessage = nil
            }
        } message: {
            Text(archiveErrorMessage ?? "")
        }
        .refreshable {
            await viewModel.load(
                serverURLString: serverURLString,
                token: token
            )
        }
    }

    @ViewBuilder
    private func recentNavigationLink(for entry: SessionRecentSection.Entry) -> some View {
        switch entry {
        case .direct(let identity, _):
            NavigationLink {
                DirectSessionDetailView(
                    serverURLString: serverURLString,
                    token: token,
                    makeViewModel: {
                        makeDirectSessionViewModel(identity)
                    },
                    onArchived: {
                        Task {
                            await viewModel.loadUpstreamSessions(
                                serverURLString: serverURLString,
                                token: token
                            )
                        }
                    }
                )
            } label: {
                RecentDirectSessionRow(identity: identity, updatedAt: entry.updatedAt)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if identity.provider == .codex {
                    Button(role: .destructive) {
                        Task {
                            let archived = await viewModel.archiveUpstreamSession(
                                identity,
                                serverURLString: serverURLString,
                                token: token
                            )
                            guard !archived else { return }
                            archiveErrorMessage = viewModel.upstreamSessionsErrorMessage ?? "Failed to archive session"
                        }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .disabled(viewModel.isArchiving(upstreamSessionID: identity.id))
                }
            }
        }
    }
}

private struct RecentDirectSessionRow: View {
    let identity: DirectSessionIdentity
    let updatedAt: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(identity.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(identity.provider.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(identity.upstreamSessionID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(Date(timeIntervalSince1970: updatedAt), style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
