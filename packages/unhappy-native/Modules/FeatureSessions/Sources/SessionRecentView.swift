import SwiftUI
import CoreKit
import FeatureSessionTools

@MainActor
public struct SessionRecentView: View {
    @ObservedObject var viewModel: SessionsViewModel
    let serverURLString: String
    let token: String
    let makeSessionToolsViewModel: @MainActor () -> SessionToolsViewModel
    let makeDirectSessionViewModel: @MainActor (DirectSessionIdentity) -> DirectSessionViewModel

    public init(
        viewModel: SessionsViewModel,
        serverURLString: String,
        token: String,
        makeSessionToolsViewModel: @escaping @MainActor () -> SessionToolsViewModel,
        makeDirectSessionViewModel: @escaping @MainActor (DirectSessionIdentity) -> DirectSessionViewModel
    ) {
        self.viewModel = viewModel
        self.serverURLString = serverURLString
        self.token = token
        self.makeSessionToolsViewModel = makeSessionToolsViewModel
        self.makeDirectSessionViewModel = makeDirectSessionViewModel
    }

    public var body: some View {
        let sections = SessionRecentPresentationBuilder.make(
            sessions: viewModel.sessions,
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
        case .direct(let row):
            NavigationLink {
                if let identity = DirectSessionIdentityResolver.resolve(from: row) {
                    DirectSessionDetailView(
                        serverURLString: serverURLString,
                        token: token,
                        makeViewModel: {
                            makeDirectSessionViewModel(identity)
                        }
                    )
                }
            } label: {
                RecentDirectSessionRow(row: row)
            }

        case .mirrored(let session):
            NavigationLink {
                SessionDetailView(
                    session: session,
                    viewModel: viewModel,
                    serverURLString: serverURLString,
                    token: token,
                    makeSessionToolsViewModel: makeSessionToolsViewModel
                )
            } label: {
                RecentSessionRow(session: session)
            }
        }
    }
}

private struct RecentSessionRow: View {
    let session: APISession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sessionDisplayTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(hasDisplayTitle ? .primary : .secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Circle()
                    .fill(session.active ? .green : .gray)
                    .frame(width: 8, height: 8)
                Text(session.active ? "Active" : "Inactive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(session.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(Date(timeIntervalSince1970: session.updatedAt), style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var normalizedDisplayTitle: String? {
        SessionDisplayTitleResolver.resolvedDisplayTitle(for: session)
    }

    private var hasDisplayTitle: Bool {
        normalizedDisplayTitle != nil
    }

    private var sessionDisplayTitle: String {
        if let normalizedDisplayTitle {
            return normalizedDisplayTitle
        }
        return SessionDisplayTitleResolver.fallbackTitle(for: session)
    }
}

private struct RecentDirectSessionRow: View {
    let row: SessionLinkedUpstreamSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(row.summary.provider.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(row.summary.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(Date(timeIntervalSince1970: row.sortTimestamp), style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
