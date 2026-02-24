import SwiftUI
import CoreKit

@MainActor
public struct SessionsView: View {
    @StateObject private var viewModel: SessionsViewModel
    private let serverURLString: String
    private let token: String
    @State private var pendingDeleteSession: APISession?

    public init(
        serverURLString: String,
        token: String,
        makeViewModel: @escaping @MainActor () -> SessionsViewModel
    ) {
        self.serverURLString = serverURLString
        self.token = token
        _viewModel = StateObject(wrappedValue: makeViewModel())
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MultiAgentStatusBanner(
                    inProgress: viewModel.multiAgentInProgress,
                    activeSessionsCount: viewModel.activeSessionsCount
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)

                if viewModel.isLoading {
                    ProgressView("Loading sessions…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage, viewModel.sessions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Unable to load sessions")
                            .font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else if viewModel.sessions.isEmpty {
                    Text("No sessions")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    List {
                        ForEach(viewModel.sessions) { session in
                            NavigationLink {
                                SessionDetailView(
                                    session: session,
                                    viewModel: viewModel,
                                    serverURLString: serverURLString,
                                    token: token
                                )
                            } label: {
                                SessionsRow(
                                    session: session,
                                    isDeleting: viewModel.isDeleting(sessionID: session.id)
                                )
                            }
                            .disabled(viewModel.isDeleting(sessionID: session.id))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDeleteSession = session
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }

                        if viewModel.hasMoreSessions {
                            HStack {
                                Spacer()
                                if viewModel.isLoadingMoreSessions {
                                    ProgressView("Loading more…")
                                        .font(.footnote)
                                } else {
                                    Button("Load more") {
                                        Task {
                                            await viewModel.loadMoreSessions(
                                                serverURLString: serverURLString,
                                                token: token
                                            )
                                        }
                                    }
                                    .font(.footnote.weight(.semibold))
                                }
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Sessions")
            .task(id: "\(serverURLString)|\(token)") {
                await viewModel.load(
                    serverURLString: serverURLString,
                    token: token
                )
                await viewModel.startPolling(
                    serverURLString: serverURLString,
                    token: token
                )
            }
            .refreshable {
                await viewModel.load(serverURLString: serverURLString, token: token)
            }
            .alert(
                "Delete session?",
                isPresented: Binding(
                    get: { pendingDeleteSession != nil },
                    set: { shouldPresent in
                        if !shouldPresent {
                            pendingDeleteSession = nil
                        }
                    }
                ),
                actions: {
                    Button("Cancel", role: .cancel) {
                        pendingDeleteSession = nil
                    }
                    Button("Delete", role: .destructive) {
                        guard let session = pendingDeleteSession else { return }
                        pendingDeleteSession = nil
                        Task {
                            await viewModel.deleteSession(
                                sessionID: session.id,
                                serverURLString: serverURLString,
                                token: token
                            )
                        }
                    }
                },
                message: {
                    Text("This removes the session permanently from the server.")
                }
            )
        }
    }
}

private struct MultiAgentStatusBanner: View {
    let inProgress: Bool
    let activeSessionsCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2.badge.gearshape")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Multi-Agent")
                .font(.subheadline.weight(.medium))
            Spacer()
            Text(activeSessionsCount == 1 ? "1 active" : "\(activeSessionsCount) active")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(inProgress ? "진행중" : "완료됨")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(inProgress ? Color.green.opacity(0.16) : Color.gray.opacity(0.14))
                .foregroundStyle(inProgress ? Color.green : Color.secondary)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SessionsRow: View {
    let session: APISession
    let isDeleting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(session.id)
                    .font(.footnote.monospaced())
                    .lineLimit(1)
                if isDeleting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            HStack(spacing: 8) {
                Circle()
                    .fill(session.active ? .green : .gray)
                    .frame(width: 8, height: 8)
                Text(session.active ? "Active" : "Inactive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Updated \(Date(timeIntervalSince1970: session.updatedAt), style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SessionsView(
        serverURLString: "https://api.unhappy.im",
        token: "",
        makeViewModel: { SessionsViewModel(service: URLSessionSessionsService()) }
    )
}
