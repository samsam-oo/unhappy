import SwiftUI
import CoreKit
import FeatureNewSession
import SessionKit

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
    private let makeNewSessionViewModel: @MainActor () -> NewSessionViewModel
    private let makeDirectSessionViewModel: @MainActor (DirectSessionIdentity) -> DirectSessionViewModel
    @State private var isPresentingProjectPicker = false
    @State private var navigationPath: [Selection] = []

    public init(
        serverURLString: String,
        token: String,
        hideInactiveSessions: Bool = false,
        defaultNewSessionAgent: APISessionSpawnAgent = .claude,
        makeViewModel: @escaping @MainActor () -> SessionsViewModel,
        makeNewSessionViewModel: @escaping @MainActor () -> NewSessionViewModel,
        makeDirectSessionViewModel: @escaping @MainActor (DirectSessionIdentity) -> DirectSessionViewModel
    ) {
        self.serverURLString = serverURLString
        self.token = token
        self.hideInactiveSessions = hideInactiveSessions
        self.defaultNewSessionAgent = defaultNewSessionAgent
        _viewModel = StateObject(wrappedValue: makeViewModel())
        self.makeNewSessionViewModel = makeNewSessionViewModel
        self.makeDirectSessionViewModel = makeDirectSessionViewModel
    }

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            sidebarContent
                .navigationTitle("Projects")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { sessionsToolbarContent }
                .refreshable {
                    await viewModel.load(serverURLString: serverURLString, token: token)
                }
                .navigationDestination(for: Selection.self) { destinationSelection in
                    destinationView(for: destinationSelection)
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
        .onChange(of: projectGroups.map(\.id)) { _, ids in
            guard let lastSelection = navigationPath.last else { return }
            switch lastSelection {
            case .project(let projectID):
                if !ids.contains(projectID) {
                    navigationPath.removeAll()
                }
            }
        }
        .sheet(isPresented: $isPresentingProjectPicker) {
            NewSessionView(
                serverURLString: serverURLString,
                token: token,
                defaultAgent: defaultNewSessionAgent,
                mode: .selectProject,
                makeViewModel: makeNewSessionViewModel,
                onProjectSelected: { machineID, directoryPath, machineDisplayName, wrappedMachineDataEncryptionKey in
                    Task {
                        await viewModel.openProject(
                            machineID: machineID ?? "",
                            machineDisplayName: machineDisplayName ?? machineID ?? "",
                            projectPath: directoryPath,
                            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
                            serverURLString: serverURLString,
                            token: token
                        )
                    }
                }
            )
        }
    }

    private func reloadSessions() async {
        await viewModel.load(
            serverURLString: serverURLString,
            token: token
        )
    }

    @ViewBuilder
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            if shouldShowFullScreenLoading {
                ProgressView("Loading sessions…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isPreparingProjectsFromLoadedSessions {
                ProgressView("Preparing projects…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let reconnectingStatusText = viewModel.reconnectingStatusText,
                      viewModel.sessions.isEmpty,
                      !hasSidebarRows {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ProgressView()
                        Text(reconnectingStatusText)
                            .font(.headline)
                        Text("The app is waiting for the machine data plane to reconnect.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .refreshable {
                    await reloadSessions()
                }
            } else if let error = viewModel.errorMessage, viewModel.sessions.isEmpty, !hasSidebarRows {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Unable to load sessions")
                            .font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .refreshable {
                    await reloadSessions()
                }
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
        ScrollView {
            VStack(spacing: 14) {
                if let projectsErrorMessage = viewModel.projectsErrorMessage,
                   !projectsErrorMessage.isEmpty {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("Unable to load projects")
                        .font(.headline)
                    Text(projectsErrorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task {
                            await reloadSessions()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
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
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.top, 24)
            .padding(.horizontal, 20)
        }
        .refreshable {
            await reloadSessions()
        }
    }

    private var sessionsNavigationList: some View {
        return List {
            if shouldShowProjectsStatusRow {
                ProjectSyncStatusRow(
                    multiAgentInProgressCount: viewModel.multiAgentInProgressCount,
                    isRefreshing: isRefreshingProjectContent,
                    reconnectingStatusText: viewModel.reconnectingStatusText
                )
                .listRowSeparator(.hidden)
            }

            Section("Projects") {
                if viewModel.isLoadingProjects && projectGroups.isEmpty {
                    ProgressView("Loading projects…")
                } else if let errorMessage = viewModel.projectsErrorMessage,
                          projectGroups.isEmpty {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(projectGroups) { group in
                        NavigationLink(value: Selection.project(group.id)) {
                            ProjectRow(group: group)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if viewModel.isTrackedProject(
                                machineID: group.machineID,
                                projectPath: group.projectPath
                            ) {
                                Button(role: .destructive) {
                                    Task {
                                        await viewModel.removeProject(
                                            machineID: group.machineID,
                                            projectPath: group.projectPath,
                                            wrappedMachineDataEncryptionKey: group.wrappedMachineDataEncryptionKey,
                                            serverURLString: serverURLString,
                                            token: token
                                        )
                                    }
                                } label: {
                                    Label("Stop Syncing", systemImage: "xmark.bin")
                                }
                                .disabled(viewModel.isRemoving(projectID: group.id))
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

    private var hasSidebarRows: Bool {
        !projectGroups.isEmpty
    }

    private var isRefreshingProjectContent: Bool {
        viewModel.isLoading || viewModel.isLoadingProjects
    }

    private var shouldShowProjectsStatusRow: Bool {
        viewModel.multiAgentInProgressCount > 0 || viewModel.reconnectingStatusText != nil
    }

    private var shouldShowFullScreenLoading: Bool {
        isRefreshingProjectContent
            && !hasSidebarRows
            && viewModel.sessions.isEmpty
    }

    private var isPreparingProjectsFromLoadedSessions: Bool {
        !viewModel.sessions.isEmpty
            && !hasSidebarRows
            && viewModel.isLoadingProjects
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
                    makeDirectSessionViewModel: makeDirectSessionViewModel
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

    private var sidebarCanvasColor: Color {
        Color(uiColor: .systemBackground)
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
                    hideInactiveSessions: hideInactiveSessions,
                    defaultNewSessionAgent: defaultNewSessionAgent,
                    makeNewSessionViewModel: makeNewSessionViewModel,
                    makeDirectSessionViewModel: makeDirectSessionViewModel,
                    onProjectRemoved: {
                        navigationPath.removeAll()
                    }
                )
            }
        }
    }

    private var projectGroups: [SessionProjectGroup] {
        SessionListPresentationBuilder.projectGroups(
            upstreamSessions: [],
            projects: viewModel.projects
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
                if let updatedLabel = SessionTimestampPresentation.updatedLabelIfKnown(for: session.updatedAt) {
                    Text("Updated \(updatedLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                if let updatedLabel = SessionTimestampPresentation.updatedLabelIfKnown(for: group.latestUpdatedAt) {
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(updatedLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(group.projectDisplayPath)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
