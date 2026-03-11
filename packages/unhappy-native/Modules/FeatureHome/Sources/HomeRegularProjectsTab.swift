import SwiftUI
import CoreKit
import SessionKit
import FeatureNewSession
import FeatureSessions

@MainActor
struct HomeRegularProjectsTab: View {
    @ObservedObject var viewModel: SessionsViewModel
    let serverURLString: String
    let token: String
    let hideInactiveSessions: Bool
    let defaultNewSessionAgent: APISessionSpawnAgent
    let makeNewSessionViewModel: @MainActor () -> NewSessionViewModel
    let makeProjectStartSheet: SessionProjectStartSheetBuilder
    let makeDirectSessionViewModel: @MainActor (DirectSessionIdentity) -> DirectSessionViewModel

    @State private var selectedProjectID: String?
    @State private var isPresentingProjectPicker = false
    @State private var isPresentingRecentSessions = false
    @State private var detailPath: [String] = []

    var body: some View {
        HStack(spacing: 0) {
            sidebarNavigation
                .frame(width: 360)
            Divider()
            detail
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task(id: "\(serverURLString)|\(token)") {
            await viewModel.load(serverURLString: serverURLString, token: token)
            await viewModel.startPolling(serverURLString: serverURLString, token: token)
        }
        .onChange(of: projectGroups.map(\.id)) { _, ids in
            let retainedSelection = HomeRegularProjectsSelectionState.retainedSelectionID(
                currentSelectionID: selectedProjectID,
                availableProjectIDs: ids
            )
            if retainedSelection != selectedProjectID {
                selectedProjectID = retainedSelection
            }
            if retainedSelection == nil, !detailPath.isEmpty {
                detailPath.removeAll()
            }
        }
        .onChange(of: selectedProjectID) { _, newSelection in
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
                if selectedProjectID != last {
                    selectedProjectID = last
                }
            } else if selectedProjectID != nil {
                selectedProjectID = nil
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
        .sheet(isPresented: $isPresentingRecentSessions) {
            NavigationStack {
                SessionRecentView(
                    viewModel: viewModel,
                    serverURLString: serverURLString,
                    token: token,
                    makeDirectSessionViewModel: makeDirectSessionViewModel
                )
            }
        }
    }

    private func reloadSessions() async {
        await viewModel.load(serverURLString: serverURLString, token: token)
    }

    private var sidebarNavigation: some View {
        NavigationStack {
            sidebar
                .navigationTitle("Projects")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { sidebarToolbar }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        Group {
            if shouldShowFullScreenLoading {
                ProgressView("Loading sessions…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isPreparingProjectsFromLoadedSessions {
                ProgressView("Preparing projects…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage, viewModel.sessions.isEmpty, !showsSessionSidebarList {
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
            } else if !showsSessionSidebarList {
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
            } else {
                List {
                    if shouldShowProjectsStatusRow {
                        ProjectSyncStatusRow(
                            multiAgentInProgressCount: viewModel.multiAgentInProgressCount,
                            isRefreshing: isRefreshingProjectContent
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
                                Button {
                                    selectedProjectID = group.id
                                } label: {
                                    HomeRegularProjectRow(
                                        group: group,
                                        isSelected: selectedProjectID == group.id
                                    )
                                }
                                .buttonStyle(.plain)
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
                .contentMargins(.top, 8, for: .scrollContent)
                .scrollContentBackground(.hidden)
                .refreshable {
                    await reloadSessions()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .systemBackground))
    }

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                isPresentingRecentSessions = true
            } label: {
                Image(systemName: "clock")
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

    private var detail: some View {
        NavigationStack(path: $detailPath) {
            VStack(spacing: 10) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Add a Project")
                    .font(.headline)
                Text("Choose a machine and project path first. Sessions inside that project will sync automatically.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationDestination(for: String.self) { projectID in
                if let group = projectGroups.first(where: { $0.id == projectID }) {
                    SessionProjectDetailView(
                        group: group,
                        viewModel: viewModel,
                        serverURLString: serverURLString,
                        token: token,
                        hideInactiveSessions: hideInactiveSessions,
                        defaultNewSessionAgent: defaultNewSessionAgent,
                        makeProjectStartSheet: makeProjectStartSheet,
                        makeDirectSessionViewModel: makeDirectSessionViewModel,
                        onProjectRemoved: {
                            selectedProjectID = nil
                            detailPath.removeAll()
                        }
                    )
                }
            }
        }
    }

    private var showsSessionSidebarList: Bool {
        !projectGroups.isEmpty
    }

    private var isRefreshingProjectContent: Bool {
        viewModel.isLoading || viewModel.isLoadingProjects
    }

    private var shouldShowProjectsStatusRow: Bool {
        viewModel.multiAgentInProgressCount > 0
    }

    private var shouldShowFullScreenLoading: Bool {
        isRefreshingProjectContent
            && !showsSessionSidebarList
            && viewModel.sessions.isEmpty
    }

    private var isPreparingProjectsFromLoadedSessions: Bool {
        !viewModel.sessions.isEmpty
            && !showsSessionSidebarList
            && viewModel.isLoadingProjects
    }

    private var projectGroups: [SessionProjectGroup] {
        SessionListPresentationBuilder.projectGroups(
            upstreamSessions: [],
            projects: viewModel.projects
        )
    }

}

struct HomeRegularProjectRow: View {
    let group: SessionProjectGroup
    let isSelected: Bool

    var body: some View {
        let updatedLabel = updatedLabel
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
                if let updatedLabel {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
    }

    private var updatedLabel: String? {
        guard group.latestUpdatedAt > 0 else {
            return nil
        }
        let interval = Date().timeIntervalSince1970 - group.latestUpdatedAt
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
