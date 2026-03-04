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

    @ViewBuilder
    private var splitDetailPlaceholder: some View {
        if viewModel.isLoading {
            ProgressView("Loading sessions…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleSessions.isEmpty {
            emptyDetailState
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
            } else if visibleSessions.isEmpty {
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
            Text("Create a new session to start coding.")
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
            Text("No sessions")
                .font(.title3.weight(.semibold))
            Text("Create a session from the left panel to begin.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                isPresentingNewSession = true
            } label: {
                Label("Create Session", systemImage: "plus")
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

    private var sessionsNavigationList: some View {
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

            loadMoreRow
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(sidebarCanvasColor)
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
        let metadata = SessionPayloadValueResolver.decodeJSONObject(
            payload: session.metadata,
            dataEncryptionKey: session.dataEncryptionKey
        )
        if let primary = bestDisplayString(
            in: metadata,
            keys: ["displayName", "name", "machineName", "deviceName", "computerName"],
            rejectGenericHosts: true,
            rejectOpaqueIdentifiers: true
        ) {
            return primary
        }
        if let host = bestDisplayString(
            in: metadata,
            keys: ["host", "hostname", "computerName", "localHostName", "hostName", "machineHost"],
            rejectGenericHosts: true,
            rejectOpaqueIdentifiers: true
        ) {
            return host
        }
        return nil
    }

    private func bestDisplayString(
        in object: Any?,
        keys: [String],
        rejectGenericHosts: Bool,
        rejectOpaqueIdentifiers: Bool
    ) -> String? {
        let normalizedKeys = Set(keys.map(normalizeKey))
        let candidates = values(in: object, matching: normalizedKeys)
        for candidate in candidates {
            if let normalized = normalizeDisplayValue(
                candidate,
                rejectGenericHosts: rejectGenericHosts,
                rejectOpaqueIdentifiers: rejectOpaqueIdentifiers
            ) {
                return normalized
            }
        }
        return nil
    }

    private func normalizeDisplayValue(
        _ raw: String,
        rejectGenericHosts: Bool,
        rejectOpaqueIdentifiers: Bool
    ) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withoutLocalSuffix = trimmed.replacingOccurrences(
            of: #"\.local$"#,
            with: "",
            options: .regularExpression
        )
        let lowered = withoutLocalSuffix.lowercased()
        let blockedValues: Set<String> = [
            "mac",
            "localhost",
            "unknown-host",
        ]
        if rejectGenericHosts && blockedValues.contains(lowered) {
            return nil
        }
        if rejectOpaqueIdentifiers && looksLikeOpaqueIdentifier(withoutLocalSuffix) {
            return nil
        }
        return withoutLocalSuffix
    }

    private func looksLikeOpaqueIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.range(
            of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        if trimmed.range(of: #"^[0-9a-fA-F]{20,}$"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"^[0-9]{10,}$"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"^[a-z0-9-]{24,}$"#, options: .regularExpression) != nil,
           trimmed.lowercased().contains("macbook") == false {
            return true
        }
        return false
    }

    private func values(in object: Any?, matching keys: Set<String>) -> [String] {
        var output: [String] = []
        collectValues(in: object, matching: keys, output: &output)
        return output
    }

    private func collectValues(
        in object: Any?,
        matching keys: Set<String>,
        output: inout [String]
    ) {
        if let dictionary = object as? [String: Any] {
            for (rawKey, value) in dictionary where keys.contains(normalizeKey(rawKey)) {
                if let string = value as? String {
                    output.append(string)
                } else if let number = value as? NSNumber {
                    output.append(number.stringValue)
                }
            }
            for (_, value) in dictionary {
                collectValues(in: value, matching: keys, output: &output)
            }
            return
        }

        if let array = object as? [Any] {
            for item in array {
                collectValues(in: item, matching: keys, output: &output)
            }
        }
    }

    private func normalizeKey(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
