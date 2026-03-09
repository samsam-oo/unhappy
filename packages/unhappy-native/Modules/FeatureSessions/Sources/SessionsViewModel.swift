import Foundation
import CoreKit

@MainActor
public final class SessionsViewModel: ObservableObject {
    private enum SyncPolicy {
        static let supportingDataRefreshInterval: TimeInterval = 15
    }

    @Published public private(set) var sessions: [APISession] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var hasMoreSessions = false
    @Published public private(set) var isLoadingMoreSessions = false
    @Published public private(set) var projects: [SessionMachineProject] = []
    @Published public private(set) var isLoadingProjects = false
    @Published public private(set) var projectsErrorMessage: String?
    @Published public private(set) var openingProjectID: String?
    @Published public private(set) var removingProjectID: String?
    @Published public private(set) var upstreamSessions: [SessionLinkedUpstreamSession] = []
    @Published public private(set) var isLoadingUpstreamSessions = false
    @Published public private(set) var upstreamSessionsErrorMessage: String?
    private var attemptedDuplicateCleanupSessionIDs: Set<String> = []

    private let loader: any SessionsLoading
    private let pageLoader: any SessionsPageLoading
    private let poller: any SessionsPolling
    private let projectsLoader: (any SessionProjectsLoadingAction)?
    private let projectOpener: (any SessionProjectOpeningAction)?
    private let projectRemover: (any SessionProjectRemovingAction)?
    private let upstreamSessionsLoader: (any SessionUpstreamSessionsLoadingAction)?
    private let deleteUseCase: any SessionDeletingAction
    private var nextCursor: String?
    private var lastSupportingDataSyncAt: TimeInterval?
    private var lastSupportingDataFingerprint: String?
    private var multiAgentInProgressCountCache = 0

    public init(
        loader: any SessionsLoading,
        pageLoader: any SessionsPageLoading,
        poller: any SessionsPolling,
        projectsLoader: (any SessionProjectsLoadingAction)? = nil,
        projectOpener: (any SessionProjectOpeningAction)? = nil,
        projectRemover: (any SessionProjectRemovingAction)? = nil,
        upstreamSessionsLoader: (any SessionUpstreamSessionsLoadingAction)? = nil,
        deleteUseCase: any SessionDeletingAction
    ) {
        self.loader = loader
        self.pageLoader = pageLoader
        self.poller = poller
        self.projectsLoader = projectsLoader
        self.projectOpener = projectOpener
        self.projectRemover = projectRemover
        self.upstreamSessionsLoader = upstreamSessionsLoader
        self.deleteUseCase = deleteUseCase
    }

    public convenience init(
        service: any SessionsFetching & SessionsPagingFetching & SessionDeleting
    ) {
        let loader = SessionsLoadUseCase(service: service)
        self.init(
            loader: loader,
            pageLoader: SessionsPageLoadUseCase(service: service),
            poller: SessionsPollingUseCase(loader: loader),
            deleteUseCase: SessionDeleteUseCase(service: service)
        )
    }

    public func isRemoving(projectID: String) -> Bool {
        removingProjectID == projectID
    }

    public func isTrackedProject(
        machineID: String,
        projectPath: String
    ) -> Bool {
        matchingTrackedProject(
            machineID: machineID,
            projectPath: projectPath
        )?.summary.openedExplicitly == true
    }

    public var multiAgentInProgressCount: Int {
        multiAgentInProgressCountCache
    }

    public func load(serverURLString: String, token: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let firstPage = try await pageLoader.loadPage(
                serverURLString: serverURLString,
                token: token,
                cursor: nil,
                limit: 50
            )
            setSessionsIfChanged(firstPage.sessions)
            await cleanupProviderBackedSessions(
                serverURLString: serverURLString,
                token: token
            )
            await cleanupMirroredDuplicateSessions(
                serverURLString: serverURLString,
                token: token
            )
            nextCursor = firstPage.nextCursor
            hasMoreSessions = firstPage.hasNext
            errorMessage = nil
            await refreshSupportingProjectContent(
                serverURLString: serverURLString,
                token: token,
                force: true
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func startPolling(
        serverURLString: String,
        token: String,
        interval: Duration = .seconds(15)
    ) async {
        isLoading = true
        errorMessage = nil

        do {
            let stream = await poller.makePollingStream(
                serverURLString: serverURLString,
                token: token,
                interval: interval
            )
            for try await rows in stream {
                setSessionsIfChanged(mergeLatestRows(rows, into: sessions))
                await cleanupProviderBackedSessions(
                    serverURLString: serverURLString,
                    token: token
                )
                await cleanupMirroredDuplicateSessions(
                    serverURLString: serverURLString,
                    token: token
                )
                await refreshSupportingProjectContent(
                    serverURLString: serverURLString,
                    token: token,
                    force: false
                )
                errorMessage = nil
                isLoading = false
            }
        } catch is CancellationError {
            // Stream cancellation is expected when the view task is torn down.
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isLoading = false
        }
    }

    public func loadMoreSessions(serverURLString: String, token: String) async {
        guard hasMoreSessions else { return }
        guard !isLoadingMoreSessions else { return }
        guard let nextCursor else {
            hasMoreSessions = false
            return
        }

        isLoadingMoreSessions = true
        defer { isLoadingMoreSessions = false }

        do {
            let page = try await pageLoader.loadPage(
                serverURLString: serverURLString,
                token: token,
                cursor: nextCursor,
                limit: 50
            )
            setSessionsIfChanged(mergeLatestRows(page.sessions, into: sessions))
            await cleanupProviderBackedSessions(
                serverURLString: serverURLString,
                token: token
            )
            await cleanupMirroredDuplicateSessions(
                serverURLString: serverURLString,
                token: token
            )
            self.nextCursor = page.nextCursor
            hasMoreSessions = page.hasNext
            errorMessage = nil
            await refreshSupportingProjectContent(
                serverURLString: serverURLString,
                token: token,
                force: false
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func loadUpstreamSessions(
        serverURLString: String,
        token: String
    ) async {
        await loadUpstreamSessions(
            serverURLString: serverURLString,
            token: token,
            projectsToSync: projectsForUpstreamSync()
        )
    }

    public func refreshProject(
        machineID: String,
        projectPath: String,
        serverURLString: String,
        token: String
    ) async {
        guard let targetProject = matchingTrackedProject(
            machineID: machineID,
            projectPath: projectPath
        ) else {
            return
        }
        guard let upstreamSessionsLoader else { return }
        guard !isLoadingUpstreamSessions else { return }

        isLoadingUpstreamSessions = true
        defer { isLoadingUpstreamSessions = false }

        do {
            let refreshedRows = try await upstreamSessionsLoader.loadUpstreamSessions(
                serverURLString: serverURLString,
                token: token,
                projects: [targetProject]
            )
            setUpstreamSessionsIfChanged(mergeProjectScopedUpstreamRows(
                existing: upstreamSessions,
                refreshed: refreshedRows,
                machineID: targetProject.machineID,
                projectPath: targetProject.summary.path
            ))
            upstreamSessionsErrorMessage = nil
        } catch {
            upstreamSessionsErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadUpstreamSessions(
        serverURLString: String,
        token: String,
        projectsToSync: [SessionMachineProject]
    ) async {
        guard let upstreamSessionsLoader else {
            upstreamSessions = []
            upstreamSessionsErrorMessage = nil
            return
        }
        guard !isLoadingUpstreamSessions else { return }

        isLoadingUpstreamSessions = true
        defer { isLoadingUpstreamSessions = false }

        if let streamingLoader = upstreamSessionsLoader as? any SessionUpstreamSessionsStreamingAction {
            for await snapshot in await streamingLoader.loadUpstreamSessionsStream(
                serverURLString: serverURLString,
                token: token,
                projects: projectsToSync
            ) {
                if let machineID = snapshot.machineID,
                   let projectPath = snapshot.projectPath {
                    setUpstreamSessionsIfChanged(
                        mergeProjectScopedUpstreamRows(
                            existing: upstreamSessions,
                            refreshed: snapshot.rows,
                            machineID: machineID,
                            projectPath: projectPath
                        )
                    )
                }
                if snapshot.errorMessage?.isEmpty == false {
                    upstreamSessionsErrorMessage = snapshot.errorMessage
                } else if snapshot.machineID != nil || snapshot.isFinal {
                    upstreamSessionsErrorMessage = nil
                }
            }
            return
        }

        do {
            let rows = try await upstreamSessionsLoader.loadUpstreamSessions(
                serverURLString: serverURLString,
                token: token,
                projects: projectsToSync
            )
            setUpstreamSessionsIfChanged(rows)
            upstreamSessionsErrorMessage = nil
        } catch {
            upstreamSessionsErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func loadProjects(
        serverURLString: String,
        token: String
    ) async {
        guard let projectsLoader else {
            projects = []
            projectsErrorMessage = nil
            return
        }
        guard !isLoadingProjects else { return }

        isLoadingProjects = true
        defer { isLoadingProjects = false }

        if let streamingProjectsLoader = projectsLoader as? any SessionProjectsStreamingAction {
            for await snapshot in await streamingProjectsLoader.loadProjectsStream(
                serverURLString: serverURLString,
                token: token
            ) {
                if let machineID = snapshot.machineID {
                    setProjectsIfChanged(
                        mergeMachineScopedProjects(
                            existing: projects,
                            refreshed: snapshot.projects.filter(\.summary.openedExplicitly),
                            machineID: machineID
                        )
                    )
                }
                if snapshot.errorMessage?.isEmpty == false {
                    projectsErrorMessage = snapshot.errorMessage
                } else if snapshot.machineID != nil || snapshot.isFinal {
                    projectsErrorMessage = nil
                }
            }
            return
        }

        do {
            let loadedProjects = try await projectsLoader.loadProjects(
                serverURLString: serverURLString,
                token: token
            ).filter(\.summary.openedExplicitly)
            setProjectsIfChanged(loadedProjects)
            projectsErrorMessage = nil
        } catch {
            projectsErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func refreshSupportingProjectContent(
        serverURLString: String,
        token: String,
        force: Bool
    ) async {
        let fingerprint = supportingDataFingerprint()
        let now = Date().timeIntervalSince1970
        let isStale: Bool
        if let lastSupportingDataSyncAt {
            isStale = now - lastSupportingDataSyncAt >= SyncPolicy.supportingDataRefreshInterval
        } else {
            isStale = true
        }

        guard force || isStale || lastSupportingDataFingerprint != fingerprint else {
            return
        }

        await loadProjects(
            serverURLString: serverURLString,
            token: token
        )
        await loadUpstreamSessions(
            serverURLString: serverURLString,
            token: token,
            projectsToSync: projectsForUpstreamSync()
        )
        lastSupportingDataFingerprint = fingerprint
        lastSupportingDataSyncAt = Date().timeIntervalSince1970
    }

    public func openProject(
        machineID: String,
        machineDisplayName: String,
        projectPath: String,
        wrappedMachineDataEncryptionKey: String?,
        serverURLString: String,
        token: String
    ) async {
        guard let projectOpener else {
            projectsErrorMessage = "Project opening is unavailable in this build"
            return
        }

        let projectID = "\(machineID)|\(projectPath)"
        openingProjectID = projectID
        defer {
            if openingProjectID == projectID {
                openingProjectID = nil
            }
        }

        do {
            let openedProject = try await projectOpener.openProject(
                serverURLString: serverURLString,
                token: token,
                machineID: machineID,
                machineDisplayName: machineDisplayName,
                path: projectPath,
                wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey
            )
            if !projects.contains(where: { $0.id == openedProject.id }) {
                projects.insert(openedProject, at: 0)
            }
                await refreshSupportingProjectContent(
                    serverURLString: serverURLString,
                    token: token,
                    force: true
                )
        } catch {
            projectsErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @discardableResult
    public func removeProject(
        machineID: String,
        projectPath: String,
        wrappedMachineDataEncryptionKey: String?,
        serverURLString: String,
        token: String
    ) async -> Bool {
        guard let projectRemover else {
            projectsErrorMessage = "Project removal is unavailable in this build"
            return false
        }

        let projectID = "\(machineID)|\(projectPath)"
        removingProjectID = projectID
        defer {
            if removingProjectID == projectID {
                removingProjectID = nil
            }
        }

        do {
            _ = try await projectRemover.removeProject(
                serverURLString: serverURLString,
                token: token,
                machineID: machineID,
                path: projectPath,
                wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey
            )
            if projects.contains(where: { $0.id == projectID }) {
                projects.removeAll { $0.id == projectID }
            }
            projectsErrorMessage = nil
            await refreshSupportingProjectContent(
                serverURLString: serverURLString,
                token: token,
                force: true
            )
            return true
        } catch {
            projectsErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private func mergeLatestRows(_ latestRows: [APISession], into existingRows: [APISession]) -> [APISession] {
        sessionsMergeLatestRows(latestRows, into: existingRows)
    }

    private func projectsForUpstreamSync() -> [SessionMachineProject] {
        projects.filter(\.summary.openedExplicitly)
    }

    private func supportingDataFingerprint() -> String {
        let trackedProjectIDs = projects.compactMap { project in
            canonicalProjectID(
                machineID: project.machineID,
                projectPath: project.summary.path
            )
        }
        .sorted()
        return trackedProjectIDs.joined(separator: ",")
    }

    private func matchingTrackedProject(
        machineID: String,
        projectPath: String
    ) -> SessionMachineProject? {
        projects.first { project in
            canonicalProjectID(
                machineID: project.machineID,
                projectPath: project.summary.path
            ) == canonicalProjectID(
                machineID: machineID,
                projectPath: projectPath
            )
        }
    }

    private func canonicalProjectID(
        machineID: String,
        projectPath: String
    ) -> String? {
        guard let normalizedPath = SessionProjectPathCanonicalizer.canonicalPath(projectPath) else {
            return nil
        }
        return "\(machineID)|\(normalizedPath)"
    }

    private func cleanupMirroredDuplicateSessions(
        serverURLString: String,
        token: String
    ) async {
        let duplicateSessionIDs = redundantMirroredSessionIDs().filter { sessionID in
            !attemptedDuplicateCleanupSessionIDs.contains(sessionID)
        }
        guard !duplicateSessionIDs.isEmpty else { return }

        for sessionID in duplicateSessionIDs {
            attemptedDuplicateCleanupSessionIDs.insert(sessionID)
            await silentlyDeleteDuplicateSession(
                sessionID: sessionID,
                serverURLString: serverURLString,
                token: token
            )
        }
    }

    private func cleanupProviderBackedSessions(
        serverURLString: String,
        token: String
    ) async {
        let sessionIDs = sessions.compactMap { session -> String? in
            guard SessionUpstreamIdentity(session: session) != nil else { return nil }
            guard !attemptedDuplicateCleanupSessionIDs.contains(session.id) else { return nil }
            return session.id
        }
        guard !sessionIDs.isEmpty else { return }

        for sessionID in sessionIDs {
            attemptedDuplicateCleanupSessionIDs.insert(sessionID)
            await silentlyDeleteDuplicateSession(
                sessionID: sessionID,
                serverURLString: serverURLString,
                token: token
            )
        }
    }

    private func redundantMirroredSessionIDs() -> [String] {
        let groupedSessions = Dictionary(
            grouping: sessions.compactMap { session -> (String, APISession)? in
                guard let key = SessionUpstreamIdentity(session: session)?.key else {
                    return nil
                }
                return (key, session)
            },
            by: \.0
        )

        return groupedSessions.values.flatMap { entries -> [String] in
            let sortedSessions = entries
                .map(\.1)
                .sorted(by: compareMirroredDuplicateSessions)
            guard sortedSessions.count > 1 else { return [] }
            return Array(sortedSessions.dropFirst().map(\.id))
        }
    }

    private func compareMirroredDuplicateSessions(
        _ lhs: APISession,
        _ rhs: APISession
    ) -> Bool {
        if lhs.active != rhs.active {
            return lhs.active && !rhs.active
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
    }

    private func silentlyDeleteDuplicateSession(
        sessionID: String,
        serverURLString: String,
        token: String
    ) async {
        do {
            try await deleteUseCase.deleteSession(
                serverURLString: serverURLString,
                token: token,
                sessionID: sessionID
            )
            if sessions.contains(where: { $0.id == sessionID }) {
                sessions.removeAll { $0.id == sessionID }
                multiAgentInProgressCountCache = sessionsMultiAgentInProgressCount(sessions)
            }
        } catch {
            // Ignore best-effort cleanup failures to avoid blocking the main session list.
        }
    }

    private func replaceSession(_ session: APISession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        var nextSessions = sessions
        nextSessions[index] = session
        setSessionsIfChanged(nextSessions)
    }

    private func mergeProjectScopedUpstreamRows(
        existing: [SessionLinkedUpstreamSession],
        refreshed: [SessionLinkedUpstreamSession],
        machineID: String,
        projectPath: String
    ) -> [SessionLinkedUpstreamSession] {
        let targetProjectID = canonicalProjectID(
            machineID: machineID,
            projectPath: projectPath
        )

        let retained = existing.filter { row in
            canonicalProjectID(
                machineID: row.machineID,
                projectPath: row.summary.cwd ?? ""
            ) != targetProjectID
        }

        var seen = Set<String>()
        let merged = (retained + refreshed).filter { row in
            seen.insert(row.id).inserted
        }

        return merged.sorted { lhs, rhs in
            if lhs.sortTimestamp != rhs.sortTimestamp {
                return lhs.sortTimestamp > rhs.sortTimestamp
            }
            if lhs.machineDisplayName != rhs.machineDisplayName {
                return lhs.machineDisplayName.localizedCaseInsensitiveCompare(rhs.machineDisplayName) == .orderedAscending
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func mergeMachineScopedProjects(
        existing: [SessionMachineProject],
        refreshed: [SessionMachineProject],
        machineID: String
    ) -> [SessionMachineProject] {
        let retained = existing.filter { $0.machineID != machineID }
        let merged = retained + refreshed
        return merged.sorted { lhs, rhs in
            let lhsDate = Date.parseISO8601(lhs.summary.latestUpdatedAt) ?? .distantPast
            let rhsDate = Date.parseISO8601(rhs.summary.latestUpdatedAt) ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            if lhs.machineDisplayName != rhs.machineDisplayName {
                return lhs.machineDisplayName.localizedCaseInsensitiveCompare(rhs.machineDisplayName) == .orderedAscending
            }
            return lhs.summary.path.localizedCaseInsensitiveCompare(rhs.summary.path) == .orderedAscending
        }
    }

    private func setSessionsIfChanged(_ nextSessions: [APISession]) {
        guard sessions != nextSessions else { return }
        sessions = nextSessions
        multiAgentInProgressCountCache = sessionsMultiAgentInProgressCount(nextSessions)
    }

    private func setProjectsIfChanged(_ nextProjects: [SessionMachineProject]) {
        guard projects != nextProjects else { return }
        projects = nextProjects
    }

    private func setUpstreamSessionsIfChanged(_ nextRows: [SessionLinkedUpstreamSession]) {
        guard upstreamSessions != nextRows else { return }
        upstreamSessions = nextRows
    }
}
