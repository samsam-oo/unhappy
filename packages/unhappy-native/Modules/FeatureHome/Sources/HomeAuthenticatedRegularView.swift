import SwiftUI
import CoreKit
import FeatureInbox
import FeatureMachine
import FeatureNewSession
import FeatureSessions
import FeatureSessionTools
import FeatureSettings

@MainActor
struct HomeAuthenticatedRegularView: View {
    private enum AuthenticatedTab: Hashable {
        case sessions
        case inbox
        case settings
    }

    @ObservedObject var settingsViewModel: SettingsViewModel
    let serverURLString: String
    let token: String
    let hideInactiveSessions: Bool
    let defaultNewSessionAgent: APISessionSpawnAgent
    let makeNewSessionViewModel: @MainActor () -> NewSessionViewModel
    let makeSessionToolsViewModel: @MainActor () -> SessionToolsViewModel
    let onSessionsChanged: @MainActor ([APISession]) async -> Void
    let makeMachinesViewModel: @MainActor () -> MachinesViewModel
    let makeUsageViewModel: @MainActor () -> UsageSettingsViewModel
    let makeDaemonStatusViewModel: @MainActor () -> ConnectorsDaemonStatusViewModel
    let makeTerminalConnectViewModel: @MainActor () -> TerminalConnectSettingsViewModel
    let makeAccountLinkViewModel: @MainActor () -> AccountLinkSettingsViewModel

    @StateObject private var inboxViewModel: InboxViewModel
    @StateObject private var sessionsViewModel: SessionsViewModel
    @State private var selectedTab: AuthenticatedTab = .sessions

    init(
        settingsViewModel: SettingsViewModel,
        serverURLString: String,
        token: String,
        hideInactiveSessions: Bool,
        defaultNewSessionAgent: APISessionSpawnAgent,
        makeInboxViewModel: @escaping @MainActor () -> InboxViewModel,
        makeSessionsViewModel: @escaping @MainActor () -> SessionsViewModel,
        makeNewSessionViewModel: @escaping @MainActor () -> NewSessionViewModel,
        makeSessionToolsViewModel: @escaping @MainActor () -> SessionToolsViewModel,
        onSessionsChanged: @escaping @MainActor ([APISession]) async -> Void,
        makeMachinesViewModel: @escaping @MainActor () -> MachinesViewModel,
        makeUsageViewModel: @escaping @MainActor () -> UsageSettingsViewModel,
        makeDaemonStatusViewModel: @escaping @MainActor () -> ConnectorsDaemonStatusViewModel,
        makeTerminalConnectViewModel: @escaping @MainActor () -> TerminalConnectSettingsViewModel,
        makeAccountLinkViewModel: @escaping @MainActor () -> AccountLinkSettingsViewModel
    ) {
        self.settingsViewModel = settingsViewModel
        self.serverURLString = serverURLString
        self.token = token
        self.hideInactiveSessions = hideInactiveSessions
        self.defaultNewSessionAgent = defaultNewSessionAgent
        self.makeNewSessionViewModel = makeNewSessionViewModel
        self.makeSessionToolsViewModel = makeSessionToolsViewModel
        self.onSessionsChanged = onSessionsChanged
        self.makeMachinesViewModel = makeMachinesViewModel
        self.makeUsageViewModel = makeUsageViewModel
        self.makeDaemonStatusViewModel = makeDaemonStatusViewModel
        self.makeTerminalConnectViewModel = makeTerminalConnectViewModel
        self.makeAccountLinkViewModel = makeAccountLinkViewModel
        _inboxViewModel = StateObject(wrappedValue: makeInboxViewModel())
        _sessionsViewModel = StateObject(wrappedValue: makeSessionsViewModel())
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeRegularInboxTab(
                viewModel: inboxViewModel,
                serverURLString: serverURLString,
                token: token
            )
            .tabItem {
                Label("Inbox", systemImage: "tray.full")
            }
            .tag(AuthenticatedTab.inbox)

            HomeRegularSessionsTab(
                viewModel: sessionsViewModel,
                serverURLString: serverURLString,
                token: token,
                hideInactiveSessions: hideInactiveSessions,
                defaultNewSessionAgent: defaultNewSessionAgent,
                makeNewSessionViewModel: makeNewSessionViewModel,
                makeSessionToolsViewModel: makeSessionToolsViewModel,
                onSessionsChanged: onSessionsChanged
            )
            .tabItem {
                Label("Sessions", systemImage: "bubble.left.and.bubble.right")
            }
            .tag(AuthenticatedTab.sessions)

            HomeRegularSettingsTab(
                viewModel: settingsViewModel,
                makeMachinesViewModel: makeMachinesViewModel,
                makeUsageViewModel: makeUsageViewModel,
                makeDaemonStatusViewModel: makeDaemonStatusViewModel,
                makeTerminalConnectViewModel: makeTerminalConnectViewModel,
                makeAccountLinkViewModel: makeAccountLinkViewModel
            )
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(AuthenticatedTab.settings)
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

private enum HomeRegularInboxSelection: Hashable {
    case friends
    case search
    case user(String)
}

@MainActor
private struct HomeRegularInboxTab: View {
    @ObservedObject var viewModel: InboxViewModel
    let serverURLString: String
    let token: String

    @State private var selection: HomeRegularInboxSelection?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 340)
            Divider()
            detail
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task(id: "\(serverURLString)|\(token)") {
            viewModel.updateConfiguration(serverURLString: serverURLString, token: token)
            await viewModel.load()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            header
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading inbox…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = viewModel.errorMessage {
                    ContentUnavailableView(
                        "Unable to load inbox",
                        systemImage: "tray.full",
                        description: Text(errorMessage)
                    )
                } else if viewModel.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("No inbox items")
                            .font(.subheadline.weight(.semibold))
                        Text("Notifications and requests will appear here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                } else {
                    list
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .systemBackground))
    }

    private var header: some View {
        HStack {
            Button {
                selection = .friends
            } label: {
                Image(systemName: "person.2")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open friends")

            Spacer()

            Text("Inbox")
                .font(.headline.weight(.semibold))

            Spacer()

            Button {
                selection = .search
            } label: {
                Image(systemName: "person.badge.plus")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search users")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var list: some View {
        List {
            if !viewModel.feedItems.isEmpty {
                Section("Updates") {
                    ForEach(viewModel.feedItems) { item in
                        if let userID = item.relatedUserID {
                            Button {
                                selection = .user(userID)
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
                            selection = .user(friend.id)
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
                            selection = .user(friend.id)
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
                            selection = .user(friend.id)
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
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemBackground))
    }

    private var detail: some View {
        NavigationStack {
            switch selection {
            case .friends:
                InboxFriendsView(viewModel: viewModel)
            case .search:
                InboxFriendSearchView(viewModel: viewModel)
            case .user(let userID):
                InboxUserProfileView(userID: userID, viewModel: viewModel)
            case .none:
                VStack(spacing: 10) {
                    Image(systemName: viewModel.isEmpty ? "tray.full" : "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(viewModel.isEmpty ? "Inbox is empty" : "Select an Inbox Item")
                        .font(.headline)
                    Text(
                        viewModel.isEmpty
                        ? "Friend requests and updates will show up here."
                        : "Choose an item from the left panel to open details."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemGroupedBackground))
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

@MainActor
private struct HomeRegularSessionsTab: View {
    private enum Selection: Hashable {
        case session(String)
        case openingUpstream(String)
    }

    @ObservedObject var viewModel: SessionsViewModel
    let serverURLString: String
    let token: String
    let hideInactiveSessions: Bool
    let defaultNewSessionAgent: APISessionSpawnAgent
    let makeNewSessionViewModel: @MainActor () -> NewSessionViewModel
    let makeSessionToolsViewModel: @MainActor () -> SessionToolsViewModel
    let onSessionsChanged: @MainActor ([APISession]) async -> Void

    @State private var selection: Selection?
    @State private var pendingDeleteSession: APISession?
    @State private var isPresentingNewSession = false
    @State private var isPresentingRecentSessions = false
    @State private var detailPath: [Selection] = []

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 360)
            Divider()
            detail
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task(id: "\(serverURLString)|\(token)") {
            await viewModel.load(serverURLString: serverURLString, token: token)
            await viewModel.startPolling(serverURLString: serverURLString, token: token)
        }
        .task(id: sessionsChangeTaskID) {
            await onSessionsChanged(viewModel.sessions)
        }
        .onChange(of: visibleSessions.map(\.id)) { _, ids in
            guard let selection else {
                self.selection = ids.first.map(Selection.session)
                return
            }
            if case .session(let sessionID) = selection, !ids.contains(sessionID) {
                self.selection = ids.first.map(Selection.session)
            }
        }
        .onChange(of: viewModel.upstreamSessions.map(\.id)) { _, ids in
            guard let selection else { return }
            if case .openingUpstream(let rowID) = selection, !ids.contains(rowID) {
                self.selection = visibleSessions.first.map { .session($0.id) }
            }
        }
        .onChange(of: selection) { _, newSelection in
            if let newSelection {
                if detailPath != [newSelection] {
                    detailPath = [newSelection]
                }
            } else if !detailPath.isEmpty {
                detailPath = []
            }
        }
        .onChange(of: detailPath) { _, newPath in
            if let last = newPath.last {
                if selection != last {
                    selection = last
                }
            } else if selection != nil {
                selection = nil
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
                        await viewModel.load(serverURLString: serverURLString, token: token)
                    }
                }
            )
        }
        .sheet(isPresented: $isPresentingRecentSessions) {
            NavigationStack {
                SessionRecentView(
                    viewModel: viewModel,
                    serverURLString: serverURLString,
                    token: token,
                    makeSessionToolsViewModel: makeSessionToolsViewModel
                )
            }
        }
    }

    private var sidebar: some View {
        let machineEntries = SessionListPresentationBuilder.machineEntries(
            sessions: visibleSessions,
            upstreamSessions: viewModel.upstreamSessions
        )
        let localSessions = SessionListPresentationBuilder.localSessions(from: visibleSessions)

        return VStack(spacing: 0) {
            HStack {
                Button {
                    isPresentingRecentSessions = true
                } label: {
                    Image(systemName: "clock")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Recent Sessions")

                Spacer()

                Text("Sessions")
                    .font(.headline.weight(.semibold))

                Spacer()

                Button {
                    isPresentingNewSession = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Session")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)

            Group {
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
                } else if !showsSessionSidebarList {
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
                } else {
                    List {
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
                                        machineEntryButton(entry)
                                    }
                                }
                            }
                        }

                        if !localSessions.isEmpty {
                            Section("Local Sessions") {
                                ForEach(localSessions) { session in
                                    Button {
                                        selection = .session(session.id)
                                    } label: {
                                        HomeRegularSessionRow(
                                            session: session,
                                            isDeleting: viewModel.isDeleting(sessionID: session.id),
                                            isSelected: selection == .session(session.id)
                                        )
                                    }
                                    .buttonStyle(.plain)
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
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .systemBackground))
    }

    private var detail: some View {
        NavigationStack(path: $detailPath) {
            VStack(spacing: 10) {
                Image(systemName: detailPlaceholderIcon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(detailPlaceholderTitle)
                    .font(.headline)
                Text(detailPlaceholderBody)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationDestination(for: Selection.self) { destination in
                switch destination {
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
                    if let upstreamSession = viewModel.upstreamSessions.first(where: { $0.id == rowID }) {
                        SessionUpstreamOpeningView(
                            row: upstreamSession,
                            viewModel: viewModel,
                            serverURLString: serverURLString,
                            token: token,
                            onLinkedSession: { linkedSessionID in
                                selection = .session(linkedSessionID)
                            }
                        )
                    }
                }
            }
        }
    }

    private var visibleSessions: [APISession] {
        if hideInactiveSessions {
            return viewModel.sessions.filter(\.active)
        }
        return viewModel.sessions
    }

    private var showsUpstreamSessionsSection: Bool {
        viewModel.isLoadingUpstreamSessions ||
        !viewModel.upstreamSessions.isEmpty ||
        viewModel.upstreamSessionsErrorMessage != nil
    }

    private var showsSessionSidebarList: Bool {
        !visibleSessions.isEmpty || showsUpstreamSessionsSection
    }

    private func showsMachineSessionsSection(machineEntries: [SessionListEntry]) -> Bool {
        !machineEntries.isEmpty || showsUpstreamSessionsSection
    }

    private var detailPlaceholderIcon: String {
        if visibleSessions.isEmpty && showsUpstreamSessionsSection {
            return "desktopcomputer"
        }
        return visibleSessions.isEmpty ? "terminal.fill" : "bubble.left.and.bubble.right.fill"
    }

    private var detailPlaceholderTitle: String {
        if visibleSessions.isEmpty && showsUpstreamSessionsSection {
            return "Open a Machine Session"
        }
        return visibleSessions.isEmpty ? "No sessions" : "Select a Session"
    }

    private var detailPlaceholderBody: String {
        if visibleSessions.isEmpty && showsUpstreamSessionsSection {
            return "Choose a machine session from the left panel to open it here."
        }
        return visibleSessions.isEmpty
            ? "Create a session from the left panel to begin."
            : "Choose a chat from the left panel to open details."
    }

    private var sessionsChangeTaskID: String {
        viewModel.sessions
            .map { session in
                "\(session.id)|\(session.active ? 1 : 0)|\(session.updatedAt)|\(session.metadataVersion)|\(session.agentStateVersion ?? -1)"
            }
            .joined(separator: ",")
    }

    @ViewBuilder
    private func machineEntryButton(_ entry: SessionListEntry) -> some View {
        switch entry {
        case .mirroredSession(let session):
            Button {
                selection = .session(session.id)
            } label: {
                HomeRegularSessionRow(
                    session: session,
                    isDeleting: viewModel.isDeleting(sessionID: session.id),
                    isSelected: selection == .session(session.id)
                )
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    pendingDeleteSession = session
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        case .upstreamSession(let row):
            Button {
                selection = .openingUpstream(row.id)
            } label: {
                HomeRegularUpstreamSessionRow(
                    row: row,
                    isLinking: viewModel.linkingUpstreamSessionID == row.id,
                    isSelected: selection == .openingUpstream(row.id)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct HomeRegularSessionRow: View {
    let session: APISession
    let isDeleting: Bool
    let isSelected: Bool

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
                Text("Updated \(updatedLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
    }

    private var normalizedDisplayTitle: String? {
        let trimmed = session.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private var hasDisplayTitle: Bool {
        normalizedDisplayTitle != nil
    }

    private var sessionDisplayTitle: String {
        if let normalizedDisplayTitle {
            return normalizedDisplayTitle
        }
        return "Session \(session.id.prefix(6))"
    }

    private var updatedLabel: String {
        let interval = Date().timeIntervalSince1970 - session.updatedAt
        if interval < 60 {
            return "just now"
        }
        if interval < 3600 {
            return "\(max(1, Int(interval / 60)))m ago"
        }
        if interval < 86400 {
            return "\(max(1, Int(interval / 3600)))h ago"
        }
        return "\(max(1, Int(interval / 86400)))d ago"
    }
}

private struct HomeRegularUpstreamSessionRow: View {
    let row: SessionLinkedUpstreamSession
    let isLinking: Bool
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                if isLinking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Text(row.summary.provider.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(row.machineDisplayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let subtitle = row.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
    }
}

private enum HomeRegularSettingsSelection: String, Hashable, CaseIterable {
    case account
    case restore
    case server
    case connectors
    case terminal
    case language
    case appearance
    case features
    case profiles
    case voice
    case usage
    case changelog
    case machines

    var title: String {
        switch self {
        case .account: return "Account"
        case .restore: return "Restore"
        case .server: return "Server"
        case .connectors: return "Connectors"
        case .terminal: return "Terminal"
        case .language: return "Language"
        case .appearance: return "Appearance"
        case .features: return "Features"
        case .profiles: return "Profiles"
        case .voice: return "Voice"
        case .usage: return "Usage"
        case .changelog: return "Changelog"
        case .machines: return "Manage Machines"
        }
    }

    var systemImage: String {
        switch self {
        case .account: return "person.crop.circle"
        case .restore: return "qrcode.viewfinder"
        case .server: return "server.rack"
        case .connectors: return "link"
        case .terminal: return "terminal"
        case .language: return "globe"
        case .appearance: return "circle.lefthalf.filled"
        case .features: return "slider.horizontal.3"
        case .profiles: return "person.2"
        case .voice: return "waveform"
        case .usage: return "chart.bar.xaxis"
        case .changelog: return "text.book.closed"
        case .machines: return "desktopcomputer"
        }
    }
}

@MainActor
private struct HomeRegularSettingsTab: View {
    @ObservedObject var viewModel: SettingsViewModel
    let makeMachinesViewModel: @MainActor () -> MachinesViewModel
    let makeUsageViewModel: @MainActor () -> UsageSettingsViewModel
    let makeDaemonStatusViewModel: @MainActor () -> ConnectorsDaemonStatusViewModel
    let makeTerminalConnectViewModel: @MainActor () -> TerminalConnectSettingsViewModel
    let makeAccountLinkViewModel: @MainActor () -> AccountLinkSettingsViewModel

    @State private var selection: HomeRegularSettingsSelection = .account

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 340)
            Divider()
            detail
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("Settings")
                    .font(.headline.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)

            List {
                Section("Connection") {
                    settingsRow(.account)
                    settingsRow(.restore)
                    settingsRow(.server)
                    settingsRow(.connectors)
                    settingsRow(.terminal)
                }

                Section("Preferences") {
                    settingsRow(.language)
                    settingsRow(.appearance)
                    settingsRow(.features)
                    settingsRow(.profiles)
                    settingsRow(.voice)
                    settingsRow(.usage)
                    settingsRow(.changelog)
                }

                Section("Machine") {
                    settingsRow(.machines)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .systemBackground))
    }

    private func settingsRow(_ item: HomeRegularSettingsSelection) -> some View {
        Button {
            selection = item
        } label: {
            HStack(spacing: 12) {
                Label(item.title, systemImage: item.systemImage)
                Spacer()
                if selection == item {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var detail: some View {
        NavigationStack {
            switch selection {
            case .account:
                AccountSettingsView(
                    viewModel: viewModel,
                    makeAccountLinkViewModel: makeAccountLinkViewModel
                )
            case .restore:
                AccountRestoreView(
                    viewModel: viewModel,
                    makeAccountLinkViewModel: makeAccountLinkViewModel
                )
            case .server:
                ServerSettingsView(viewModel: viewModel)
            case .connectors:
                ConnectorsSettingsView(
                    serverURLString: viewModel.serverURLString,
                    token: viewModel.apiToken,
                    makeDaemonStatusViewModel: makeDaemonStatusViewModel
                )
            case .terminal:
                TerminalConnectSettingsView(
                    serverURLString: viewModel.serverURLString,
                    token: viewModel.apiToken,
                    makeViewModel: makeTerminalConnectViewModel
                )
            case .language:
                LanguageSettingsView(viewModel: viewModel)
            case .appearance:
                AppearanceSettingsView(viewModel: viewModel)
            case .features:
                FeaturesSettingsView(viewModel: viewModel)
            case .profiles:
                ProfilesSettingsView(viewModel: viewModel)
            case .voice:
                VoiceSettingsView(viewModel: viewModel)
            case .usage:
                UsageSettingsView(
                    serverURLString: viewModel.serverURLString,
                    token: viewModel.apiToken,
                    makeViewModel: makeUsageViewModel
                )
            case .changelog:
                ChangelogView()
                    .onAppear {
                        viewModel.markLatestChangelogViewed()
                    }
            case .machines:
                MachinesView(
                    serverURLString: viewModel.serverURLString,
                    token: viewModel.apiToken,
                    makeViewModel: makeMachinesViewModel
                )
            }
        }
    }
}
