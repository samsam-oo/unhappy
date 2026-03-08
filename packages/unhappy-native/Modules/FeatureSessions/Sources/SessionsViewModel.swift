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

    public var multiAgentInProgress: Bool {
        if isLoading {
            return true
        }
        return sessions.contains(where: { $0.active })
    }

    public var activeSessionsCount: Int {
        sessions.filter(\.active).count
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
            sessions = firstPage.sessions
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
                sessions = mergeLatestRows(rows, into: sessions)
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
            sessions = mergeLatestRows(page.sessions, into: sessions)
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

        do {
            let rows = try await upstreamSessionsLoader.loadUpstreamSessions(
                serverURLString: serverURLString,
                token: token,
                projects: projectsToSync
            )
            upstreamSessions = rows
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

        do {
            projects = try await projectsLoader.loadProjects(
                serverURLString: serverURLString,
                token: token
            ).filter(\.summary.openedExplicitly)
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
        lastSupportingDataFingerprint = supportingDataFingerprint()
        lastSupportingDataSyncAt = Date().timeIntervalSince1970
    }

    public func openProject(
        machineID: String,
        machineDisplayName: String,
        projectPath: String,
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
                path: projectPath
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
                path: projectPath
            )
            projects.removeAll { $0.id == projectID }
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
            sessions.removeAll { $0.id == sessionID }
        } catch {
            // Ignore best-effort cleanup failures to avoid blocking the main session list.
        }
    }

    private func replaceSession(_ session: APISession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        var nextSessions = sessions
        nextSessions[index] = session
        sessions = nextSessions
    }
}
