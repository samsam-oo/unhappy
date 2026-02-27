import SwiftUI
import CoreKit
import FeatureNewSession
import FeatureSessionTools

@MainActor
public struct SessionsView: View {
    @StateObject private var viewModel: SessionsViewModel
    private let serverURLString: String
    private let token: String
    private let hideInactiveSessions: Bool
    private let defaultNewSessionAgent: APISessionSpawnAgent
    private let onSessionsChanged: @MainActor ([APISession]) async -> Void
    private let makeNewSessionViewModel: @MainActor () -> NewSessionViewModel
    private let makeSessionToolsViewModel: @MainActor () -> SessionToolsViewModel
    @State private var pendingDeleteSession: APISession?
    @State private var isPresentingNewSession = false

    public init(
        serverURLString: String,
        token: String,
        hideInactiveSessions: Bool = false,
        defaultNewSessionAgent: APISessionSpawnAgent = .claude,
        onSessionsChanged: @escaping @MainActor ([APISession]) async -> Void = { _ in },
        makeViewModel: @escaping @MainActor () -> SessionsViewModel,
        makeNewSessionViewModel: @escaping @MainActor () -> NewSessionViewModel,
        makeSessionToolsViewModel: @escaping @MainActor () -> SessionToolsViewModel
    ) {
        self.serverURLString = serverURLString
        self.token = token
        self.hideInactiveSessions = hideInactiveSessions
        self.defaultNewSessionAgent = defaultNewSessionAgent
        self.onSessionsChanged = onSessionsChanged
        _viewModel = StateObject(wrappedValue: makeViewModel())
        self.makeNewSessionViewModel = makeNewSessionViewModel
        self.makeSessionToolsViewModel = makeSessionToolsViewModel
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                } else if visibleSessions.isEmpty {
                    Text("No sessions")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    List {
                        ForEach(visibleSessions) { session in
                            NavigationLink {
                                SessionDetailView(
                                    session: session,
                                    viewModel: viewModel,
                                    serverURLString: serverURLString,
                                    token: token,
                                    makeSessionToolsViewModel: makeSessionToolsViewModel
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SessionRecentView(
                            viewModel: viewModel,
                            serverURLString: serverURLString,
                            token: token,
                            makeSessionToolsViewModel: makeSessionToolsViewModel
                        )
                    } label: {
                        Label("Recent", systemImage: "clock")
                    }
                    .accessibilityLabel("Recent Sessions")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingNewSession = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("New Session")
                }
            }
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
            .task(id: sessionsChangeTaskID) {
                await onSessionsChanged(viewModel.sessions)
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
                    Text("This first tries to terminate the local session process, then permanently deletes the session record from the server. Project files and directories are not deleted.")
                }
            )
            .sheet(isPresented: $isPresentingNewSession) {
                NewSessionView(
                    serverURLString: serverURLString,
                    token: token,
                    defaultAgent: defaultNewSessionAgent,
                    makeViewModel: makeNewSessionViewModel,
                    onSessionSpawned: { _ in
                        Task {
                            await viewModel.load(
                                serverURLString: serverURLString,
                                token: token
                            )
                        }
                    }
                )
            }
        }
    }

    private var visibleSessions: [APISession] {
        if hideInactiveSessions {
            return viewModel.sessions.filter(\.active)
        }
        return viewModel.sessions
    }

    private var sessionsChangeTaskID: String {
        viewModel.sessions
            .map { session in
                "\(session.id)|\(session.active ? 1 : 0)|\(session.updatedAt)|\(session.metadataVersion)|\(session.agentStateVersion ?? -1)"
            }
            .joined(separator: ",")
    }
}

private struct SessionsRow: View {
    let session: APISession
    let isDeleting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(sessionDisplayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(hasDisplayTitle ? .primary : .secondary)
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
                Text(session.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Text("Updated \(SessionTimestampPresentation.updatedLabel(for: session.updatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var normalizedDisplayTitle: String? {
        guard let raw = session.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              raw != session.id else {
            return nil
        }
        return raw
    }

    private var hasDisplayTitle: Bool {
        normalizedDisplayTitle != nil
    }

    private var sessionDisplayTitle: String {
        if let normalizedDisplayTitle {
            return normalizedDisplayTitle
        }
        if let seq = session.seq, seq > 0 {
            return "Session #\(seq)"
        }
        return "Session"
    }
}

#Preview {
    SessionsView(
        serverURLString: "https://api.unhappy.im",
        token: "",
        makeViewModel: { SessionsViewModel(service: URLSessionSessionsService()) },
        makeNewSessionViewModel: {
            let service = URLSessionMachinesService()
            return NewSessionViewModel(
                machinesLoader: NewSessionMachinesLoadUseCase(service: service),
                directoryLister: NewSessionDirectoryListUseCase(service: service),
                spawner: NewSessionSpawnUseCase(service: service),
                recentProjectsManager: NewSessionNoopRecentProjectsManager(),
                profilesManager: NewSessionNoopProfilesManager(),
                modelsLoader: NewSessionModelsLoadUseCase(service: service),
                codexThreadsLoader: NewSessionCodexThreadsLoadUseCase(service: service),
                claudeSessionsLoader: NewSessionClaudeSessionsLoadUseCase(service: service)
            )
        },
        makeSessionToolsViewModel: {
            let service = URLSessionSessionsService()
            let basher = SessionBashUseCase(service: service)
            return SessionToolsViewModel(
                fileLoader: SessionFileLoadUseCase(service: service),
                directoryLister: SessionDirectoryListUseCase(service: service),
                fileWriter: SessionFileWriteUseCase(service: service),
                fileDiffPreviewer: SessionFileDiffPreviewUseCase(basher: basher),
                killer: SessionKillUseCase(service: service),
                aborter: SessionTaskAbortUseCase(service: service),
                permissionResponder: SessionPermissionUseCase(service: service),
                modeSwitcher: SessionModeSwitchUseCase(service: service),
                basher: basher,
                ripgrepRunner: SessionRipgrepUseCase(service: service),
                difftasticRunner: SessionDifftasticUseCase(service: service)
            )
        }
    )
}
