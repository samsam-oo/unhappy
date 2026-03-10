import SwiftUI
import CoreKit
import FeatureNewSession
import UIFoundation

@MainActor
public struct SessionProjectDetailView: View {
    private enum SessionListEntry: Identifiable {
        case direct(SessionLinkedUpstreamSession, DirectSessionIdentity, updatedAt: TimeInterval)

        var id: String {
            switch self {
            case .direct(_, let identity, _):
                return "direct:\(identity.machineID)|\(identity.provider.rawValue)|\(identity.upstreamSessionID)"
            }
        }

        var sortTimestamp: TimeInterval {
            switch self {
            case .direct(_, _, let updatedAt):
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
    @State private var archiveErrorMessage: String?

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
        .task(id: group.id) {
            if sessionEntries.isEmpty {
                await viewModel.refreshProject(
                    machineID: group.machineID,
                    projectPath: group.projectPath,
                    serverURLString: serverURLString,
                    token: token
                )
            }
        }
        .refreshable {
            await viewModel.refreshProject(
                machineID: group.machineID,
                projectPath: group.projectPath,
                serverURLString: serverURLString,
                token: token
            )
        }
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { projectActionsToolbar }
        .alert(
            "Couldn't Archive Session",
            isPresented: Binding(
                get: { archiveErrorMessage?.isEmpty == false },
                set: { isPresented in
                    if !isPresented {
                        archiveErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                archiveErrorMessage = nil
            }
        } message: {
            Text(archiveErrorMessage ?? "")
        }
        .navigationDestination(item: $spawnedDirectSessionIdentity) { identity in
            DirectSessionDetailView(
                serverURLString: serverURLString,
                token: token,
                makeViewModel: {
                    makeDirectSessionViewModel(identity)
                },
                onArchived: {
                    Task {
                        await viewModel.refreshProject(
                            machineID: group.machineID,
                            projectPath: group.projectPath,
                            serverURLString: serverURLString,
                            token: token
                        )
                    }
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
                        let resolvedMachineID = context.machineID ?? group.machineID
                        await viewModel.refreshProject(
                            machineID: resolvedMachineID,
                            projectPath: context.directoryPath,
                            serverURLString: serverURLString,
                            token: token
                        )
                        let provider: APIUpstreamSessionProvider
                        switch context.agent {
                        case .codex:
                            provider = .codex
                        case .claude:
                            provider = .claude
                        case .gemini:
                            provider = .gemini
                        }
                        if let directRow = viewModel.upstreamSessions.first(where: {
                            $0.machineID == resolvedMachineID &&
                            $0.summary.provider == provider &&
                            $0.summary.id == sessionID
                        }), let identity = DirectSessionIdentityResolver.resolve(from: directRow) {
                            spawnedDirectSessionIdentity = identity
                            return
                        }
                        let fallbackProvider: APIUpstreamSessionProvider
                        switch context.agent {
                        case .codex:
                            fallbackProvider = .codex
                        case .gemini:
                            fallbackProvider = .gemini
                        case .claude:
                            fallbackProvider = .claude
                        }
                        spawnedDirectSessionIdentity = DirectSessionIdentity(
                            machineID: resolvedMachineID,
                            machineDisplayName: group.machineDisplayName,
                            wrappedMachineDataEncryptionKey: group.wrappedMachineDataEncryptionKey,
                            provider: fallbackProvider,
                            upstreamSessionID: sessionID,
                            title: "Session",
                            cwd: context.directoryPath,
                            transcriptPath: nil,
                            model: context.model,
                            effort: nil,
                            permissionMode: nil,
                            collabInProgressCount: 0
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
                                wrappedMachineDataEncryptionKey: group.wrappedMachineDataEncryptionKey,
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
            upstreamSessions: viewModel.upstreamSessions,
            projects: viewModel.projects
        ) ?? initialGroup
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
                    Text(group.projectDisplayPath)
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
            return SessionListEntry.direct(row, identity, updatedAt: row.sortTimestamp)
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
        case .direct(let row, let identity, let updatedAt):
            NavigationLink {
                DirectSessionDetailView(
                    serverURLString: serverURLString,
                    token: token,
                    makeViewModel: {
                        makeDirectSessionViewModel(identity)
                    },
                    onArchived: {
                        Task {
                            await viewModel.refreshProject(
                                machineID: group.machineID,
                                projectPath: group.projectPath,
                                serverURLString: serverURLString,
                                token: token
                            )
                        }
                    }
                )
            } label: {
                ProjectDirectSessionRow(identity: identity, updatedAt: updatedAt)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if row.summary.provider == .codex {
                    Button(role: .destructive) {
                        Task {
                            await archiveSession(identity: identity)
                        }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .disabled(viewModel.isArchiving(upstreamSessionID: identity.id))
                }
            }
        }
    }

    private func archiveSession(identity: DirectSessionIdentity) async {
        let archived = await viewModel.archiveUpstreamSession(
            identity,
            serverURLString: serverURLString,
            token: token
        )
        guard archived else {
            archiveErrorMessage = viewModel.upstreamSessionsErrorMessage ?? "Failed to archive session"
            return
        }
    }
}

private struct ProjectDirectSessionRow: View {
    let identity: DirectSessionIdentity
    let updatedAt: TimeInterval

    var body: some View {
        let updatedLabel = SessionTimestampPresentation.updatedLabelIfKnown(for: updatedAt)
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
                if let updatedLabel {
                    Text("Updated \(updatedLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let model = identity.model, !model.isEmpty {
                    if updatedLabel != nil {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
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
