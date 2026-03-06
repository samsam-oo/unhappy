import SwiftUI
import CoreKit
import FeatureNewSession
import FeatureSessionTools

@MainActor
public struct SessionsView: View {
    private enum Selection: Hashable {
        case session(String)
        case openingUpstream(String)
    }

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
    @State private var selection: Selection?

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
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
                .navigationTitle("Sessions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { sessionsToolbarContent }
                .refreshable {
                    await viewModel.load(serverURLString: serverURLString, token: token)
                }
        } detail: {
            splitDetailPlaceholder
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(detailCanvasColor)
        }
        .navigationSplitViewStyle(.balanced)
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
        .onChange(of: visibleSessions.map(\.id)) { _, ids in
            guard let selection else { return }
            if case .session(let sessionID) = selection, !ids.contains(sessionID) {
                self.selection = nil
            }
        }
        .onChange(of: viewModel.upstreamSessions.map(\.id)) { _, ids in
            guard let selection else { return }
            if case .openingUpstream(let rowID) = selection, !ids.contains(rowID) {
                self.selection = nil
            }
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
        .navigationDestination(for: Selection.self) { destinationSelection in
            destinationView(for: destinationSelection)
        }
    }

    @ViewBuilder
    private var splitDetailPlaceholder: some View {
        if viewModel.isLoading {
            ProgressView("Loading sessions…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let selection {
            destinationView(for: selection)
        } else if !hasSidebarRows {
            emptyDetailState
        } else if visibleSessions.isEmpty {
            openMachineSessionDetailState
        } else {
            chooseSessionDetailState
        }
    }

    @ViewBuilder
    private var sidebarContent: some View {
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
            } else if !hasSidebarRows {
                emptySidebarState
            } else {
                sessionsNavigationList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(sidebarCanvasColor)
    }

    private var emptySidebarState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("No sessions yet")
                .font(.headline)
            Text("Create a new session or attach one from a connected machine.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                isPresentingNewSession = true
            } label: {
                Label("New Session", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 24)
        .padding(.horizontal, 20)
    }

    private var emptyDetailState: some View {
        VStack(spacing: 14) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(emptyDetailTitle)
                .font(.title3.weight(.semibold))
            Text(emptyDetailBody)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                isPresentingNewSession = true
            } label: {
                Label(emptyDetailButtonTitle, systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
    }

    private var chooseSessionDetailState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Select a Session")
                .font(.headline)
            Text("Choose a chat from the left panel to open details.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
    }

    private var openMachineSessionDetailState: some View {
        VStack(spacing: 10) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Open a Machine Session")
                .font(.headline)
            Text("Choose a machine session from the left panel to open it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
    }

    private var sessionsNavigationList: some View {
        let machineEntries = SessionListPresentationBuilder.machineEntries(
            sessions: visibleSessions,
            upstreamSessions: viewModel.upstreamSessions
        )
        let localSessions = SessionListPresentationBuilder.localSessions(from: visibleSessions)

        return List(selection: $selection) {
            if showsMachineSessionsSection(machineEntries: machineEntries) {
                Section("Machine Sessions") {
                    if viewModel.isLoadingUpstreamSessions && machineEntries.isEmpty {
                        ProgressView("Loading live sessions…")
                    } else if let errorMessage = viewModel.upstreamSessionsErrorMessage,
                              machineEntries.isEmpty {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(machineEntries) { entry in
                            machineNavigationLink(entry)
                        }
                    }
                }
            }

            if !localSessions.isEmpty {
                Section("Local Sessions") {
                    ForEach(localSessions) { session in
                        NavigationLink(value: Selection.session(session.id)) {
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
                }
            }

            loadMoreRow
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(sidebarCanvasColor)
    }

    private var showsUpstreamSessionsSection: Bool {
        viewModel.isLoadingUpstreamSessions ||
        !viewModel.upstreamSessions.isEmpty ||
        viewModel.upstreamSessionsErrorMessage != nil
    }

    private var hasSidebarRows: Bool {
        !visibleSessions.isEmpty || showsUpstreamSessionsSection
    }

    private func showsMachineSessionsSection(machineEntries: [SessionListEntry]) -> Bool {
        !machineEntries.isEmpty || showsUpstreamSessionsSection
    }

    private var emptyDetailTitle: String {
        showsUpstreamSessionsSection ? "Open a Machine Session" : "No sessions"
    }

    private var emptyDetailBody: String {
        showsUpstreamSessionsSection
            ? "Open a machine session from the left panel or create a new one."
            : "Create a session from the left panel to begin."
    }

    private var emptyDetailButtonTitle: String {
        showsUpstreamSessionsSection ? "Create New Session" : "Create Session"
    }

    @ViewBuilder
    private var loadMoreRow: some View {
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

    @ToolbarContentBuilder
    private var sessionsToolbarContent: some ToolbarContent {
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

    private var sidebarCanvasColor: Color {
        Color(uiColor: .systemBackground)
    }

    private var detailCanvasColor: Color {
        Color(uiColor: .systemGroupedBackground)
    }

    @ViewBuilder
    private func machineNavigationLink(_ entry: SessionListEntry) -> some View {
        switch entry {
        case .mirroredSession(let session):
            NavigationLink(value: Selection.session(session.id)) {
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
        case .upstreamSession(let row):
            NavigationLink(value: Selection.openingUpstream(row.id)) {
                VStack(alignment: .leading, spacing: 6) {
                    UpstreamSessionRow(
                        summary: row.summary,
                        isLinking: viewModel.linkingUpstreamSessionID == row.id
                    )
                    HStack(spacing: 6) {
                        Text(row.summary.provider.displayName)
                            .font(.caption2.weight(.semibold))
                        Text("·")
                            .font(.caption2)
                        Text(row.machineDisplayName)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func destinationView(for selection: Selection) -> some View {
        switch selection {
        case .session(let sessionID):
            if let session = visibleSessions.first(where: { $0.id == sessionID }) {
                SessionDetailView(
                    session: session,
                    viewModel: viewModel,
                    serverURLString: serverURLString,
                    token: token,
                    makeSessionToolsViewModel: makeSessionToolsViewModel
                )
            }
        case .openingUpstream(let rowID):
            if let row = viewModel.upstreamSessions.first(where: { $0.id == rowID }) {
                SessionUpstreamOpeningView(
                    row: row,
                    viewModel: viewModel,
                    serverURLString: serverURLString,
                    token: token,
                    onLinkedSession: { linkedSessionID in
                        self.selection = .session(linkedSessionID)
                    }
                )
            }
        }
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
                if let machineDisplayName {
                    Label(machineDisplayName, systemImage: "desktopcomputer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("Updated \(SessionTimestampPresentation.updatedLabel(for: session.updatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(session.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
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

    private var machineDisplayName: String? {
        SessionUpstreamIdentity(session: session)?.machineDisplayName
    }
}
