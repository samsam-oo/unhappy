import SwiftUI
import CoreKit
import FeatureSessionTools

@MainActor
struct SessionRecentView: View {
    @ObservedObject var viewModel: SessionsViewModel
    let serverURLString: String
    let token: String
    let makeSessionToolsViewModel: @MainActor () -> SessionToolsViewModel

    var body: some View {
        let sections = SessionRecentPresentationBuilder.make(sessions: viewModel.sessions)

        List {
            if sections.isEmpty {
                Text("No recent sessions")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.sessions) { session in
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
