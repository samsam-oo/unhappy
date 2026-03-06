import SwiftUI
import CoreKit
import FeatureNewSession
import FeatureSessionTools

@MainActor
public struct SessionsView: View {
    private enum Selection: Hashable {
        case project(String)
    }

    @StateObject private var viewModel: SessionsViewModel
    private let serverURLString: String
    private let token: String
    private let hideInactiveSessions: Bool
    private let defaultNewSessionAgent: APISessionSpawnAgent
    private let onSessionsChanged: @MainActor ([APISession]) async -> Void
    private let makeNewSessionViewModel: @MainActor () -> NewSessionViewModel
    private let makeSessionToolsViewModel: @MainActor () -> SessionToolsViewModel
    @State private var isPresentingProjectPicker = false
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
                .navigationTitle("Projects")
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
        .onChange(of: projectGroups.map(\.id)) { _, ids in
            guard let selection else {
                self.selection = projectGroups.first.map { .project($0.id) }
                return
            }
            if case .project(let projectID) = selection, !ids.contains(projectID) {
                self.selection = nil
            }
        }
        .sheet(isPresented: $isPresentingProjectPicker) {
            NewSessionView(
                serverURLString: serverURLString,
                token: token,
                defaultAgent: defaultNewSessionAgent,
                mode: .selectProject,
                makeViewModel: makeNewSessionViewModel,
                onProjectSelected: { machineID, directoryPath, machineDisplayName in
                    viewModel.addProjectBookmark(
                        machineID: machineID ?? "",
                        machineDisplayName: machineDisplayName ?? machineID ?? "",
                        projectPath: directoryPath
                    )
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
            ProgressView("Loading projects…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let selection {
            destinationView(for: selection)
        } else if !hasSidebarRows {
            emptyDetailState
        } else if let firstProject = projectGroups.first {
            SessionProjectDetailView(
                group: firstProject,
                viewModel: viewModel,
                serverURLString: serverURLString,
                token: token,
                defaultNewSessionAgent: defaultNewSessionAgent,
                makeNewSessionViewModel: makeNewSessionViewModel,
                makeSessionToolsViewModel: makeSessionToolsViewModel
            )
        } else {
            emptyDetailState
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
            Text("No projects yet")
                .font(.headline)
            Text("Add a project to start syncing its sessions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                isPresentingProjectPicker = true
            } label: {
                Label("Add Project", systemImage: "plus.circle.fill")
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
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Add a Project")
                .font(.title3.weight(.semibold))
            Text("Choose a machine and project path first. Sessions inside that project will sync automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                isPresentingProjectPicker = true
            } label: {
                Label("Add Project", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
    }

    private var sessionsNavigationList: some View {
        return List(selection: $selection) {
            Section("Projects") {
                if viewModel.isLoadingUpstreamSessions && projectGroups.isEmpty {
                    ProgressView("Loading projects…")
                } else if let errorMessage = viewModel.upstreamSessionsErrorMessage,
                          projectGroups.isEmpty {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(projectGroups) { group in
                        NavigationLink(value: Selection.project(group.id)) {
                            ProjectRow(group: group)
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
        !projectGroups.isEmpty
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
                isPresentingProjectPicker = true
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .accessibilityLabel("Add Project")
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
    private func destinationView(for selection: Selection) -> some View {
        switch selection {
        case .project(let projectID):
            if let group = projectGroups.first(where: { $0.id == projectID }) {
                SessionProjectDetailView(
                    group: group,
                    viewModel: viewModel,
                    serverURLString: serverURLString,
                    token: token,
                    defaultNewSessionAgent: defaultNewSessionAgent,
                    makeNewSessionViewModel: makeNewSessionViewModel,
                    makeSessionToolsViewModel: makeSessionToolsViewModel
                )
            }
        }
    }

    private var projectGroups: [SessionProjectGroup] {
        SessionListPresentationBuilder.projectGroups(
            sessions: visibleSessions,
            upstreamSessions: viewModel.upstreamSessions,
            bookmarks: viewModel.projectBookmarks
        )
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

private struct ProjectRow: View {
    let group: SessionProjectGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(group.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("\(group.allSessionCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text(group.machineDisplayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(SessionTimestampPresentation.updatedLabel(for: group.latestUpdatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if group.activeSessionCount > 0 {
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(group.activeSessionCount) active")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            Text(group.projectPath)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
