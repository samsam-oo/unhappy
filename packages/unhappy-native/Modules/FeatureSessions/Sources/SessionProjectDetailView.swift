import SwiftUI
import CoreKit
import FeatureNewSession
import FeatureSessionTools

@MainActor
public struct SessionProjectDetailView: View {
    private enum SessionListEntry: Identifiable {
        case mirrored(APISession)
        case upstream(SessionLinkedUpstreamSession)

        var id: String {
            switch self {
            case .mirrored(let session):
                return "mirrored:\(session.id)"
            case .upstream(let row):
                return "upstream:\(row.id)"
            }
        }

        var sortTimestamp: TimeInterval {
            switch self {
            case .mirrored(let session):
                return session.updatedAt
            case .upstream(let row):
                return row.sortTimestamp
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
    let makeSessionToolsViewModel: @MainActor () -> SessionToolsViewModel
    let makeDirectSessionViewModel: @MainActor (DirectSessionIdentity) -> DirectSessionViewModel
    let onProjectRemoved: (() -> Void)?

    @State private var isPresentingNewSession = false
    @State private var isPresentingProjectActions = false
    @State private var firstMessagePreviewBySessionID: [String: String] = [:]
    @State private var spawnedSessionNavigationSessionID: String?

    public init(
        group: SessionProjectGroup,
        viewModel: SessionsViewModel,
        serverURLString: String,
        token: String,
        hideInactiveSessions: Bool,
        defaultNewSessionAgent: APISessionSpawnAgent,
        makeNewSessionViewModel: @escaping @MainActor () -> NewSessionViewModel,
        makeSessionToolsViewModel: @escaping @MainActor () -> SessionToolsViewModel,
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
        self.makeSessionToolsViewModel = makeSessionToolsViewModel
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
        .task(id: firstMessagePreviewTaskID) {
            await loadMissingFirstMessagePreviews()
        }
        .navigationDestination(item: $spawnedSessionNavigationSessionID) { sessionID in
            if let session = viewModel.sessions.first(where: { $0.id == sessionID }) {
                SessionDetailView(
                    session: session,
                    viewModel: viewModel,
                    serverURLString: serverURLString,
                    token: token,
                    makeSessionToolsViewModel: makeSessionToolsViewModel
                )
            } else {
                ProgressView("Opening session…")
            }
        }
        .sheet(isPresented: $isPresentingNewSession) {
            NewSessionView(
                serverURLString: serverURLString,
                token: token,
                defaultAgent: defaultNewSessionAgent,
                initialMachineID: group.machineID,
                initialDirectoryPath: group.projectPath,
                makeViewModel: makeNewSessionViewModel,
                onSessionSpawned: { sessionID in
                    guard let sessionID else { return }
                    Task {
                        if let session = await viewModel.refreshAndSelectSession(
                            sessionID: sessionID,
                            serverURLString: serverURLString,
                            token: token
                        ) {
                            spawnedSessionNavigationSessionID = session.id
                        }
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
        let combined = group.displayMirroredSessions.map(SessionListEntry.mirrored)
            + group.displayUpstreamSessions.map(SessionListEntry.upstream)
        return combined.sorted { lhs, rhs in
            if lhs.sortTimestamp != rhs.sortTimestamp {
                return lhs.sortTimestamp > rhs.sortTimestamp
            }
            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
    }

    @ViewBuilder
    private func sessionRow(for entry: SessionListEntry) -> some View {
        switch entry {
        case .mirrored(let session):
            NavigationLink {
                SessionDetailView(
                    session: session,
                    viewModel: viewModel,
                    serverURLString: serverURLString,
                    token: token,
                    makeSessionToolsViewModel: makeSessionToolsViewModel
                )
            } label: {
                ProjectMirroredSessionRow(
                    sessionDisplayTitle: mirroredSessionDisplayTitle(for: session),
                    sessionPreview: mirroredSessionSecondaryPreview(for: session),
                    providerLabel: mirroredSessionProviderLabel(for: session),
                    isDisplayTitlePrimary: SessionDisplayTitleResolver.resolvedDisplayTitle(for: session) != nil,
                    sessionIsActive: session.active,
                    sessionUpdatedAt: session.updatedAt,
                    isDeleting: viewModel.isDeleting(sessionID: session.id)
                )
            }
            .disabled(viewModel.isDeleting(sessionID: session.id))

        case .upstream(let row):
            NavigationLink {
                SessionUpstreamOpeningView(
                    row: row,
                    serverURLString: serverURLString,
                    token: token,
                    makeDirectSessionViewModel: makeDirectSessionViewModel
                )
            } label: {
                ProjectUpstreamSessionRow(row: row)
            }
        }
    }

    private var firstMessagePreviewTaskID: String {
        group.displayMirroredSessions
            .map { session in
                "\(session.id)|\(session.updatedAt)|\(session.metadataVersion)|\(session.agentStateVersion ?? -1)"
            }
            .joined(separator: ",")
    }

    private func mirroredSessionDisplayTitle(for session: APISession) -> String {
        if let resolvedTitle = SessionDisplayTitleResolver.resolvedDisplayTitle(for: session) {
            return resolvedTitle
        }
        if let firstMessagePreview = firstMessagePreviewBySessionID[session.id] {
            return firstMessagePreview
        }
        return SessionDisplayTitleResolver.fallbackTitle(for: session)
    }

    private func mirroredSessionSecondaryPreview(for session: APISession) -> String? {
        guard SessionDisplayTitleResolver.resolvedDisplayTitle(for: session) != nil else {
            return nil
        }
        guard let firstMessagePreview = firstMessagePreviewBySessionID[session.id] else {
            return nil
        }
        guard firstMessagePreview != mirroredSessionDisplayTitle(for: session) else {
            return nil
        }
        return firstMessagePreview
    }

    private func mirroredSessionProviderLabel(for session: APISession) -> String? {
        SessionRuntimeContext(session: session).provider?.displayName
    }

    private func loadMissingFirstMessagePreviews() async {
        let pendingSessions = group.displayMirroredSessions.filter { session in
            SessionDisplayTitleResolver.resolvedDisplayTitle(for: session) == nil
                && firstMessagePreviewBySessionID[session.id] == nil
        }
        guard !pendingSessions.isEmpty else { return }

        for session in pendingSessions {
            let preview = await viewModel.loadFirstMessagePreview(
                for: session.id,
                dataEncryptionKey: session.dataEncryptionKey,
                serverURLString: serverURLString,
                token: token
            )
            if let preview, !preview.isEmpty {
                firstMessagePreviewBySessionID[session.id] = preview
            }
        }
    }

}

private struct ProjectMirroredSessionRow: View {
    let sessionDisplayTitle: String
    let sessionPreview: String?
    let providerLabel: String?
    let isDisplayTitlePrimary: Bool
    let sessionIsActive: Bool
    let sessionUpdatedAt: TimeInterval
    let isDeleting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(sessionDisplayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isDisplayTitlePrimary ? .primary : .secondary)
                    .lineLimit(1)
                if let providerLabel {
                    Text(providerLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if isDeleting {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let sessionPreview {
                Text(sessionPreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(sessionIsActive ? .green : .gray)
                    .frame(width: 8, height: 8)
                Text(sessionIsActive ? "Active" : "Inactive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Updated \(SessionTimestampPresentation.updatedLabel(for: sessionUpdatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct ProjectUpstreamSessionRow: View {
    let row: SessionLinkedUpstreamSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(rowDisplayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(hasExplicitTitle ? .primary : .secondary)
                    .lineLimit(1)

                Text(row.summary.provider.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let normalizedPreview, normalizedPreview != rowDisplayTitle {
                Text(normalizedPreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Text("Updated \(updatedLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let model = normalizedModel {
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

    private var normalizedTitle: String? {
        let title = row.summary.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        guard title.localizedCaseInsensitiveCompare("Untitled") != .orderedSame else { return nil }
        return title
    }

    private var hasExplicitTitle: Bool {
        normalizedTitle != nil
    }

    private var rowDisplayTitle: String {
        if let normalizedTitle {
            return normalizedTitle
        }
        if let normalizedPreview {
            return normalizedPreview
        }
        return row.summary.id
    }

    private var updatedLabel: String {
        SessionTimestampPresentation.updatedLabel(for: row.sortTimestamp)
    }

    private var normalizedPreview: String? {
        let preview = row.summary.preview?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let preview, !preview.isEmpty else { return nil }
        return preview
    }

    private var normalizedModel: String? {
        let model = row.summary.model?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let model, !model.isEmpty else { return nil }
        return model
    }
}
