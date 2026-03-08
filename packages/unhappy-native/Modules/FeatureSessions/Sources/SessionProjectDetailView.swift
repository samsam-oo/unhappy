import SwiftUI
import CoreKit
import FeatureNewSession

@MainActor
public struct SessionProjectDetailView: View {
    private enum SessionListEntry: Identifiable {
        case direct(DirectSessionIdentity, updatedAt: TimeInterval)

        var id: String {
            switch self {
            case .direct(let identity, _):
                return "direct:\(identity.machineID)|\(identity.provider.rawValue)|\(identity.upstreamSessionID)"
            }
        }

        var sortTimestamp: TimeInterval {
            switch self {
            case .direct(_, let updatedAt):
                return updatedAt
            }
        }
    }

    let initialGroup: SessionProjectGroup
    @ObservedObject var viewModel: SessionsViewModel
    let serverURLString: String
    let token: String
    let hideInactiveSessions: Bool
    let defaultNewSessionAgent: APISessionSpawnAgent
    let makeNewSessionViewModel: @MainActor () -> NewSessionViewModel
    let makeDirectSessionViewModel: @MainActor (DirectSessionIdentity) -> DirectSessionViewModel
    let onProjectRemoved: (() -> Void)?

    @State private var isPresentingNewSession = false
    @State private var isPresentingProjectActions = false
    @State private var spawnedDirectSessionIdentity: DirectSessionIdentity?

    public init(
        group: SessionProjectGroup,
        viewModel: SessionsViewModel,
        serverURLString: String,
        token: String,
        hideInactiveSessions: Bool,
        defaultNewSessionAgent: APISessionSpawnAgent,
        makeNewSessionViewModel: @escaping @MainActor () -> NewSessionViewModel,
        makeDirectSessionViewModel: @escaping @MainActor (DirectSessionIdentity) -> DirectSessionViewModel,
        onProjectRemoved: (() -> Void)? = nil
    ) {
        self.initialGroup = group
        self.viewModel = viewModel
        self.serverURLString = serverURLString
        self.token = token
        self.hideInactiveSessions = hideInactiveSessions
        self.defaultNewSessionAgent = defaultNewSessionAgent
        self.makeNewSessionViewModel = makeNewSessionViewModel
        self.makeDirectSessionViewModel = makeDirectSessionViewModel
        self.onProjectRemoved = onProjectRemoved
    }

    public var body: some View {
        List {
            Section {
                summaryCard
            }

            if sessionEntries.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No sessions yet")
                            .font(.headline)
                        Text("Start a new session in this project and it will appear here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Section("Sessions") {
                    ForEach(sessionEntries) { entry in
                        sessionRow(for: entry)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { projectActionsToolbar }
        .navigationDestination(item: $spawnedDirectSessionIdentity) { identity in
            DirectSessionDetailView(
                serverURLString: serverURLString,
                token: token,
                makeViewModel: {
                    makeDirectSessionViewModel(identity)
                }
            )
        }
        .sheet(isPresented: $isPresentingNewSession) {
            NewSessionView(
                serverURLString: serverURLString,
                token: token,
                defaultAgent: defaultNewSessionAgent,
                initialMachineID: group.machineID,
                initialDirectoryPath: group.projectPath,
                makeViewModel: makeNewSessionViewModel,
                onSessionSpawned: { context in
                    guard let sessionID = context.sessionID else { return }
                    Task {
                        guard context.agent == .codex || context.agent == .claude else {
                            return
                        }
                        await viewModel.load(serverURLString: serverURLString, token: token)
                        if let directRow = viewModel.upstreamSessions.first(where: {
                            $0.machineID == (context.machineID ?? "") &&
                            $0.summary.provider == (context.agent == .codex ? .codex : .claude) &&
                            $0.summary.id == sessionID
                        }), let identity = DirectSessionIdentityResolver.resolve(from: directRow) {
                            spawnedDirectSessionIdentity = identity
                            return
                        }
                        let fallbackProvider: APIUpstreamSessionProvider = context.agent == .codex ? .codex : .claude
                        spawnedDirectSessionIdentity = DirectSessionIdentity(
                            machineID: context.machineID ?? group.machineID,
                            machineDisplayName: group.machineDisplayName,
                            provider: fallbackProvider,
                            upstreamSessionID: sessionID,
                            title: "Session",
                            cwd: context.directoryPath,
                            transcriptPath: nil,
                            model: context.model
                        )
                    }
                }
            )
        }
    }

    @ToolbarContentBuilder
    private var projectActionsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isPresentingNewSession = true
            } label: {
                Image(systemName: "plus")
            }
            .disabled(!group.hasConcreteProjectPath)
            .accessibilityLabel("New Session")
        }

        if viewModel.isTrackedProject(
            machineID: group.machineID,
            projectPath: group.projectPath
        ) {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingProjectActions = true
                } label: {
                    if viewModel.isRemoving(projectID: group.id) {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                .accessibilityLabel("Project Actions")
                .confirmationDialog(
                    "Project Actions",
                    isPresented: $isPresentingProjectActions,
                    titleVisibility: .visible
                ) {
                    Button("Stop Syncing Project", role: .destructive) {
                        Task {
                            let didRemove = await viewModel.removeProject(
                                machineID: group.machineID,
                                projectPath: group.projectPath,
                                serverURLString: serverURLString,
                                token: token
                            )
                            if didRemove {
                                onProjectRemoved?()
                            }
                        }
                    }
                    .disabled(viewModel.isRemoving(projectID: group.id))
                }
            }
        }
    }

    private var group: SessionProjectGroup {
        SessionListPresentationBuilder.projectGroup(
            id: initialGroup.id,
            sessions: visibleSessions,
            upstreamSessions: viewModel.upstreamSessions,
            projects: viewModel.projects
        ) ?? initialGroup
    }

    private var visibleSessions: [APISession] {
        if hideInactiveSessions {
            return viewModel.sessions.filter(\.active)
        }
        return viewModel.sessions
    }

    private var summaryCard: some View {
        SessionSurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(group.machineDisplayName)
                        .modifier(DockChipModifier(tone: .neutral))
                    Text("\(sessionEntries.count) sessions")
                        .modifier(DockChipModifier(tone: .primary))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.projectPath)
                        .font(.body.monospaced())
                        .foregroundStyle(AppPalette.primaryText)
                        .textSelection(.enabled)
                    Text("Choose a session to continue where you left off, or start a fresh one in the same project context.")
                        .font(.footnote)
                        .foregroundStyle(AppPalette.secondaryText)
                }
            }
            .padding(16)
        }
    }

    private var sessionEntries: [SessionListEntry] {
        let directEntries: [SessionListEntry] = group.displayUpstreamSessions.compactMap { row in
            guard let identity = DirectSessionIdentityResolver.resolve(from: row) else {
                return nil
            }
            return SessionListEntry.direct(identity, updatedAt: row.sortTimestamp)
        }
        return directEntries.sorted { lhs, rhs in
            if lhs.sortTimestamp != rhs.sortTimestamp {
                return lhs.sortTimestamp > rhs.sortTimestamp
            }
            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
    }

    @ViewBuilder
    private func sessionRow(for entry: SessionListEntry) -> some View {
        switch entry {
        case .direct(let identity, let updatedAt):
            NavigationLink {
                DirectSessionDetailView(
                    serverURLString: serverURLString,
                    token: token,
                    makeViewModel: {
                        makeDirectSessionViewModel(identity)
                    }
                )
            } label: {
                ProjectDirectSessionRow(identity: identity, updatedAt: updatedAt)
            }
        }
    }
}

private struct ProjectDirectSessionRow: View {
    let identity: DirectSessionIdentity
    let updatedAt: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(identity.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(identity.provider.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text("Updated \(SessionTimestampPresentation.updatedLabel(for: updatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let model = identity.model, !model.isEmpty {
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(model)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
