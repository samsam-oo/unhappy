import Foundation
import CoreKit
import SessionKit

@MainActor
public final class SessionsViewModel: ObservableObject {
    private enum SyncPolicy {
        static let supportingDataRefreshInterval: TimeInterval = 15
        static let initialPollingGraceInterval: Duration = .seconds(2)
    }

    @Published public private(set) var sessions: [APISession] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var reconnectingStatusText: String?
    @Published public private(set) var hasMoreSessions = false
    @Published public private(set) var isLoadingMoreSessions = false
    @Published public private(set) var projects: [SessionMachineProject] = []
    @Published public private(set) var isLoadingProjects = false
    @Published public private(set) var projectsErrorMessage: String?
    @Published public private(set) var openingProjectID: String?
    @Published public private(set) var removingProjectID: String?
    @Published public private(set) var archivingUpstreamSessionID: String?
    @Published public private(set) var upstreamSessions: [SessionLinkedUpstreamSession] = []
    @Published public private(set) var recentCatalogSessions: [SessionLinkedUpstreamSession] = []
    @Published public private(set) var isLoadingRecentCatalogSessions = false
    @Published public private(set) var recentCatalogSessionsErrorMessage: String?
    @Published public private(set) var isLoadingUpstreamSessions = false
    @Published public private(set) var upstreamSessionsErrorMessage: String?
    private var attemptedDuplicateCleanupSessionIDs: Set<String> = []

    private let loader: any SessionsLoading
    private let pageLoader: any SessionsPageLoading
    private let poller: any SessionsPolling
    private let projectsLoader: (any SessionProjectsLoadingAction)?
    private let projectSessionsLoader: (any SessionProjectSessionsLoadingAction)?
    private let projectOpener: (any SessionProjectOpeningAction)?
    private let projectRemover: (any SessionProjectRemovingAction)?
    private let upstreamSessionsLoader: (any SessionUpstreamSessionsLoadingAction)?
    private let recentCatalogSessionsLoader: (any SessionRecentCatalogLoadingAction)?
    private let upstreamSessionArchiver: (any DirectSessionArchivingAction)?
    private let deleteUseCase: any SessionDeletingAction
    private var nextCursor: String?
    private var lastSupportingDataSyncAt: TimeInterval?
    private var lastSupportingDataFingerprint: String?
    private var multiAgentInProgressCountCache = 0
    private var activeUpstreamScopeIDs: Set<String> = []
    private var resolvedUpstreamScopeIDs: Set<String> = []
    private var activeUpstreamLoadCount = 0
    private var activeProjectSessionScopeIDs: Set<String> = []
    private var resolvedProjectSessionScopeIDs: Set<String> = []
    @Published public private(set) var projectScopedSessions: [String: [SessionLinkedUpstreamSession]] = [:]
    @Published public private(set) var projectScopedSessionErrors: [String: String] = [:]
    private var supportingDataTask: Task<Void, Never>?
    private var lastPrimarySessionLoadAt: TimeInterval?

    public init(
        loader: any SessionsLoading,
        pageLoader: any SessionsPageLoading,
        poller: any SessionsPolling,
        projectsLoader: (any SessionProjectsLoadingAction)? = nil,
        projectSessionsLoader: (any SessionProjectSessionsLoadingAction)? = nil,
        projectOpener: (any SessionProjectOpeningAction)? = nil,
        projectRemover: (any SessionProjectRemovingAction)? = nil,
        upstreamSessionsLoader: (any SessionUpstreamSessionsLoadingAction)? = nil,
        recentCatalogSessionsLoader: (any SessionRecentCatalogLoadingAction)? = nil,
        upstreamSessionArchiver: (any DirectSessionArchivingAction)? = nil,
        deleteUseCase: any SessionDeletingAction
    ) {
        self.loader = loader
        self.pageLoader = pageLoader
        self.poller = poller
        self.projectsLoader = projectsLoader
        self.projectSessionsLoader = projectSessionsLoader
        self.projectOpener = projectOpener
        self.projectRemover = projectRemover
        self.upstreamSessionsLoader = upstreamSessionsLoader
        self.recentCatalogSessionsLoader = recentCatalogSessionsLoader
        self.upstreamSessionArchiver = upstreamSessionArchiver
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

    deinit {
        supportingDataTask?.cancel()
    }

    public func isRemoving(projectID: String) -> Bool {
        removingProjectID == projectID
    }

    public func isArchiving(upstreamSessionID: String) -> Bool {
        archivingUpstreamSessionID == upstreamSessionID
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

    public func isProjectSessionsLoading(
        machineID: String,
        projectPath: String
    ) -> Bool {
        guard let scopeID = canonicalProjectID(machineID: machineID, projectPath: projectPath) else {
            return false
        }
        return activeProjectSessionScopeIDs.contains(scopeID)
    }

    public func hasLoadedProjectSessions(
        machineID: String,
        projectPath: String
    ) -> Bool {
        guard let scopeID = canonicalProjectID(machineID: machineID, projectPath: projectPath) else {
            return false
        }
        return resolvedProjectSessionScopeIDs.contains(scopeID)
    }

    public func projectSessions(
        machineID: String,
        projectPath: String
    ) -> [SessionLinkedUpstreamSession] {
        guard let scopeID = canonicalProjectID(machineID: machineID, projectPath: projectPath) else {
            return []
        }
        return projectScopedSessions[scopeID] ?? []
    }

    public func projectSessionsError(
        machineID: String,
        projectPath: String
    ) -> String? {
        guard let scopeID = canonicalProjectID(machineID: machineID, projectPath: projectPath) else {
            return nil
        }
        return projectScopedSessionErrors[scopeID]
    }

    public var aggregatedProjectRows: [SessionLinkedUpstreamSession] {
        var rowsByID: [String: SessionLinkedUpstreamSession] = [:]
        for row in upstreamSessions {
            rowsByID[row.id] = row
        }
        for rows in projectScopedSessions.values {
            for row in rows {
                let existing = rowsByID[row.id]
                if let existing, existing.sortTimestamp >= row.sortTimestamp {
                    continue
                }
                rowsByID[row.id] = row
            }
        }
        return rowsByID.values.sorted { lhs, rhs in
            if lhs.sortTimestamp != rhs.sortTimestamp {
                return lhs.sortTimestamp > rhs.sortTimestamp
            }
            if lhs.machineDisplayName != rhs.machineDisplayName {
                return lhs.machineDisplayName.localizedCaseInsensitiveCompare(rhs.machineDisplayName) == .orderedAscending
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    public var aggregatedRecentSessions: [SessionLinkedUpstreamSession] {
        var rowsByID: [String: SessionLinkedUpstreamSession] = [:]
        for row in aggregatedProjectRows {
            rowsByID[row.id] = row
        }
        for row in recentCatalogSessions {
            let existing = rowsByID[row.id]
            if let existing, existing.sortTimestamp >= row.sortTimestamp {
                continue
            }
            rowsByID[row.id] = row
        }
        return rowsByID.values.sorted { lhs, rhs in
            if lhs.sortTimestamp != rhs.sortTimestamp {
                return lhs.sortTimestamp > rhs.sortTimestamp
            }
            if lhs.machineDisplayName != rhs.machineDisplayName {
                return lhs.machineDisplayName.localizedCaseInsensitiveCompare(rhs.machineDisplayName) == .orderedAscending
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    public func loadRecentCatalogSessions(
        serverURLString: String,
        token: String
    ) async {
        guard let recentCatalogSessionsLoader else { return }
        guard !isLoadingRecentCatalogSessions else { return }

        isLoadingRecentCatalogSessions = true
        defer { isLoadingRecentCatalogSessions = false }

        do {
            let rows = try await recentCatalogSessionsLoader.loadRecentSessions(
                serverURLString: serverURLString,
                token: token
            )
            if recentCatalogSessions != rows {
                recentCatalogSessions = rows
            }
            recentCatalogSessionsErrorMessage = nil
        } catch {
            recentCatalogSessionsErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func load(serverURLString: String, token: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        scheduleSupportingDataRefresh(
            serverURLString: serverURLString,
            token: token,
            force: true
        )

        do {
            let firstPage = try await pageLoader.loadPage(
                serverURLString: serverURLString,
                token: token,
                cursor: nil,
                limit: 50
            )
            setSessionsIfChanged(firstPage.sessions)
            nextCursor = firstPage.nextCursor
            hasMoreSessions = firstPage.hasNext
            lastPrimarySessionLoadAt = Date().timeIntervalSince1970
            errorMessage = nil
            reconnectingStatusText = nil
            isLoading = false
        } catch {
            applyPrimaryLoadError(error)
            isLoading = false
        }
    }

    public func startPolling(
        serverURLString: String,
        token: String,
        interval: Duration = .seconds(15)
    ) async {
        if sessions.isEmpty {
            isLoading = true
        }
        errorMessage = nil

        do {
            if shouldDelayInitialPolling {
                try await Task.sleep(for: SyncPolicy.initialPollingGraceInterval)
            }
            let stream = await poller.makePollingStream(
                serverURLString: serverURLString,
                token: token,
                interval: interval
            )
            for try await rows in stream {
                setSessionsIfChanged(mergeLatestRows(rows, into: sessions))
                lastPrimarySessionLoadAt = Date().timeIntervalSince1970
                scheduleSupportingDataRefresh(
                    serverURLString: serverURLString,
                    token: token,
                    force: false
                )
                errorMessage = nil
                reconnectingStatusText = nil
                isLoading = false
            }
        } catch is CancellationError {
            // Stream cancellation is expected when the view task is torn down.
        } catch {
            applyPrimaryLoadError(error)
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
            reconnectingStatusText = nil
            await refreshSupportingProjectContent(
                serverURLString: serverURLString,
                token: token,
                force: false
            )
        } catch {
            applyPrimaryLoadError(error)
        }
    }

    public func loadUpstreamSessions(
        serverURLString: String,
        token: String
    ) async {
        guard shouldLoadGlobalUpstreamState else {
            setUpstreamSessionsIfChanged([])
            upstreamSessionsErrorMessage = nil
            isLoadingUpstreamSessions = false
            return
        }
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
        if let projectSessionsLoader {
            await refreshProjectScopedSessions(
                project: targetProject,
                loader: projectSessionsLoader,
                serverURLString: serverURLString,
                token: token
            )
            return
        }
        guard let upstreamSessionsLoader else { return }
        let acceptedProjects = beginUpstreamLoad(for: [targetProject])
        guard !acceptedProjects.isEmpty else { return }
        defer { endUpstreamLoad(for: acceptedProjects) }

        if let streamingLoader = upstreamSessionsLoader as? any SessionUpstreamSessionsStreamingAction {
            for await snapshot in await streamingLoader.loadUpstreamSessionsStream(
                serverURLString: serverURLString,
                token: token,
                projects: acceptedProjects
            ) {
                if let machineID = snapshot.machineID,
                   let scopedProjectPath = snapshot.projectPath {
                    setUpstreamSessionsIfChanged(
                        mergeProjectScopedUpstreamRows(
                            existing: upstreamSessions,
                            refreshed: snapshot.rows,
                            machineID: machineID,
                            projectPath: scopedProjectPath
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
            let refreshedRows = try await upstreamSessionsLoader.loadUpstreamSessions(
                serverURLString: serverURLString,
                token: token,
                projects: acceptedProjects
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
        if let projectSessionsLoader {
            let acceptedProjects = beginUpstreamLoad(for: projectsToSync)
            guard !acceptedProjects.isEmpty else {
                upstreamSessionsErrorMessage = nil
                isLoadingUpstreamSessions = false
                return
            }
            defer { endUpstreamLoad(for: acceptedProjects) }

            struct ProjectSessionBatch: Sendable {
                let scopeID: String
                let project: SessionMachineProject
                let rows: [SessionLinkedUpstreamSession]
                let errorMessage: String?
            }

            let scopedProjects = acceptedProjects.compactMap { project -> (String, SessionMachineProject)? in
                guard let scopeID = canonicalProjectID(
                    machineID: project.machineID,
                    projectPath: project.summary.path
                ) else {
                    return nil
                }
                return (scopeID, project)
            }
            let activeScopedProjects = scopedProjects.filter { scopeID, _ in
                activeProjectSessionScopeIDs.insert(scopeID).inserted
            }
            defer {
                for (scopeID, _) in activeScopedProjects {
                    activeProjectSessionScopeIDs.remove(scopeID)
                    resolvedProjectSessionScopeIDs.insert(scopeID)
                }
            }

            var firstErrorMessage: String?
            await withTaskGroup(of: ProjectSessionBatch.self) { group in
                for (scopeID, project) in activeScopedProjects {
                    group.addTask {
                        do {
                            let rows = try await projectSessionsLoader.loadProjectSessions(
                                serverURLString: serverURLString,
                                token: token,
                                project: project
                            )
                            return ProjectSessionBatch(
                                scopeID: scopeID,
                                project: project,
                                rows: rows,
                                errorMessage: nil
                            )
                        } catch {
                            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                            let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
                            return ProjectSessionBatch(
                                scopeID: scopeID,
                                project: project,
                                rows: [],
                                errorMessage: normalizedMessage.isEmpty ? nil : normalizedMessage
                            )
                        }
                    }
                }

                for await batch in group {
                    if batch.errorMessage == nil {
                        if projectScopedSessions[batch.scopeID] != batch.rows {
                            projectScopedSessions[batch.scopeID] = batch.rows
                        }
                        projectScopedSessionErrors[batch.scopeID] = nil
                        setUpstreamSessionsIfChanged(
                            mergeProjectScopedUpstreamRows(
                                existing: upstreamSessions,
                                refreshed: batch.rows,
                                machineID: batch.project.machineID,
                                projectPath: batch.project.summary.path
                            )
                        )
                    } else {
                        projectScopedSessionErrors[batch.scopeID] = batch.errorMessage
                    }
                    if firstErrorMessage == nil,
                       let errorMessage = batch.errorMessage,
                       !errorMessage.isEmpty {
                        firstErrorMessage = errorMessage
                    }
                }
            }
            upstreamSessionsErrorMessage = firstErrorMessage
            return
        }

        guard let upstreamSessionsLoader else {
            upstreamSessions = []
            upstreamSessionsErrorMessage = nil
            return
        }
        let acceptedProjects = beginUpstreamLoad(for: projectsToSync)
        guard !acceptedProjects.isEmpty else {
            setUpstreamSessionsIfChanged([])
            upstreamSessionsErrorMessage = nil
            isLoadingUpstreamSessions = false
            return
        }
        defer { endUpstreamLoad(for: acceptedProjects) }

        if let streamingLoader = upstreamSessionsLoader as? any SessionUpstreamSessionsStreamingAction {
            for await snapshot in await streamingLoader.loadUpstreamSessionsStream(
                serverURLString: serverURLString,
                token: token,
                projects: acceptedProjects
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
                projects: acceptedProjects
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
                let refreshedProjects = snapshot.projects.filter(\.summary.openedExplicitly)
                if let machineID = snapshot.machineID {
                    setProjectsIfChanged(
                        mergeMachineScopedProjects(
                            existing: projects,
                            refreshed: refreshedProjects,
                            machineID: machineID
                        )
                    )
                    if shouldHydrateProjectScopedSessionsForLists, !refreshedProjects.isEmpty {
                        scheduleIncrementalUpstreamLoad(
                            projects: refreshedProjects,
                            serverURLString: serverURLString,
                            token: token
                        )
                    }
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

        let usesIncrementalSupportingStreams =
            (projectsLoader as? any SessionProjectsStreamingAction) != nil &&
            (
                shouldHydrateProjectScopedSessionsForLists ||
                shouldLoadGlobalUpstreamState && (upstreamSessionsLoader as? any SessionUpstreamSessionsStreamingAction) != nil
            )

        await loadProjects(
            serverURLString: serverURLString,
            token: token
        )
        if recentCatalogSessionsLoader != nil {
            await loadRecentCatalogSessions(
                serverURLString: serverURLString,
                token: token
            )
        }
        if !usesIncrementalSupportingStreams {
            await loadUpstreamSessions(
                serverURLString: serverURLString,
                token: token,
                projectsToSync: projectsForUpstreamSync()
            )
        }
        lastSupportingDataFingerprint = fingerprint
        lastSupportingDataSyncAt = Date().timeIntervalSince1970
    }

    private func applyPrimaryLoadError(_ error: Error) {
        if let reconnectingStatusText = MachinesAPIError.reconnectingStatusText(from: error) {
            self.reconnectingStatusText = reconnectingStatusText
            errorMessage = nil
            return
        }
        reconnectingStatusText = nil
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
            _ = try await projectOpener.openProject(
                serverURLString: serverURLString,
                token: token,
                machineID: machineID,
                machineDisplayName: machineDisplayName,
                path: projectPath,
                wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey
            )
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
        let targetCanonicalProjectID = canonicalProjectID(
            machineID: machineID,
            projectPath: projectPath
        )
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
            setProjectsIfChanged(
                projects.filter { project in
                    guard let targetCanonicalProjectID else {
                        return project.id != projectID
                    }
                    return canonicalProjectID(
                        machineID: project.machineID,
                        projectPath: project.summary.path
                    ) != targetCanonicalProjectID
                }
            )
            projectsErrorMessage = nil
            Task { [weak self] in
                guard let self else { return }
                await self.refreshSupportingProjectContent(
                    serverURLString: serverURLString,
                    token: token,
                    force: true
                )
            }
            return true
        } catch {
            projectsErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func archiveUpstreamSession(
        _ identity: DirectSessionIdentity,
        serverURLString: String,
        token: String
    ) async -> Bool {
        guard let upstreamSessionArchiver else {
            upstreamSessionsErrorMessage = "Session archiving is unavailable in this build"
            return false
        }

        let upstreamSessionID = identity.id
        archivingUpstreamSessionID = upstreamSessionID
        defer {
            if archivingUpstreamSessionID == upstreamSessionID {
                archivingUpstreamSessionID = nil
            }
        }

        do {
            try await upstreamSessionArchiver.archiveSession(
                serverURLString: serverURLString,
                token: token,
                identity: identity
            )
            if upstreamSessions.contains(where: { $0.id == upstreamSessionID }) {
                upstreamSessions.removeAll { $0.id == upstreamSessionID }
            }
            upstreamSessionsErrorMessage = nil
            await refreshProject(
                machineID: identity.machineID,
                projectPath: identity.cwd,
                serverURLString: serverURLString,
                token: token
            )
            return true
        } catch {
            upstreamSessionsErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private func mergeLatestRows(_ latestRows: [APISession], into existingRows: [APISession]) -> [APISession] {
        sessionsMergeLatestRows(latestRows, into: existingRows)
    }

    private func scheduleIncrementalUpstreamLoad(
        projects: [SessionMachineProject],
        serverURLString: String,
        token: String
    ) {
        guard shouldHydrateProjectScopedSessionsForLists || shouldLoadGlobalUpstreamState else {
            return
        }
        Task { [weak self] in
            guard let self else { return }
            await self.loadUpstreamSessions(
                serverURLString: serverURLString,
                token: token,
                projectsToSync: projects
            )
        }
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

    private func refreshProjectScopedSessions(
        project: SessionMachineProject,
        loader: any SessionProjectSessionsLoadingAction,
        serverURLString: String,
        token: String
    ) async {
        guard let scopeID = canonicalProjectID(
            machineID: project.machineID,
            projectPath: project.summary.path
        ) else {
            return
        }
        guard activeProjectSessionScopeIDs.insert(scopeID).inserted else { return }
        defer {
            activeProjectSessionScopeIDs.remove(scopeID)
            resolvedProjectSessionScopeIDs.insert(scopeID)
        }

        do {
            let rows = try await loader.loadProjectSessions(
                serverURLString: serverURLString,
                token: token,
                project: project
            )
            if projectScopedSessions[scopeID] != rows {
                projectScopedSessions[scopeID] = rows
            }
            projectScopedSessionErrors[scopeID] = nil
            setUpstreamSessionsIfChanged(
                mergeProjectScopedUpstreamRows(
                    existing: upstreamSessions,
                    refreshed: rows,
                    machineID: project.machineID,
                    projectPath: project.summary.path
                )
            )
        } catch {
            projectScopedSessionErrors[scopeID] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func beginUpstreamLoad(
        for projects: [SessionMachineProject]
    ) -> [SessionMachineProject] {
        var acceptedProjects: [SessionMachineProject] = []
        for project in projects {
            guard let scopeID = canonicalProjectID(
                machineID: project.machineID,
                projectPath: project.summary.path
            ) else {
                continue
            }
            guard activeUpstreamScopeIDs.insert(scopeID).inserted else {
                continue
            }
            acceptedProjects.append(project)
        }
        if !acceptedProjects.isEmpty {
            activeUpstreamLoadCount += 1
            isLoadingUpstreamSessions = true
        }
        return acceptedProjects
    }

    private func endUpstreamLoad(
        for projects: [SessionMachineProject]
    ) {
        guard !projects.isEmpty else { return }
        for project in projects {
            if let scopeID = canonicalProjectID(
                machineID: project.machineID,
                projectPath: project.summary.path
            ) {
                activeUpstreamScopeIDs.remove(scopeID)
                resolvedUpstreamScopeIDs.insert(scopeID)
            }
        }
        activeUpstreamLoadCount = max(0, activeUpstreamLoadCount - 1)
        isLoadingUpstreamSessions = activeUpstreamLoadCount > 0
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
        let filteredSessions = nextSessions.filter { session in
            SessionUpstreamIdentity(session: session) == nil
        }
        guard sessions != filteredSessions else { return }
        sessions = filteredSessions
        multiAgentInProgressCountCache = sessionsMultiAgentInProgressCount(filteredSessions)
    }

    private func setProjectsIfChanged(_ nextProjects: [SessionMachineProject]) {
        let allowedScopeIDs = Set(
            nextProjects
                .filter(\.summary.openedExplicitly)
                .compactMap { project in
                    canonicalProjectID(
                        machineID: project.machineID,
                        projectPath: project.summary.path
                    )
                }
        )
        let filteredUpstreamRows = upstreamSessions.filter { row in
            guard let scopeID = canonicalProjectID(
                machineID: row.machineID,
                projectPath: row.summary.cwd ?? ""
            ) else {
                return false
            }
            return allowedScopeIDs.contains(scopeID)
        }
        let filteredProjectScopedSessions = projectScopedSessions.filter { allowedScopeIDs.contains($0.key) }
        let filteredProjectScopedSessionErrors = projectScopedSessionErrors.filter { allowedScopeIDs.contains($0.key) }
        let filteredResolvedProjectSessionScopeIDs = resolvedProjectSessionScopeIDs.intersection(allowedScopeIDs)

        guard
            projects != nextProjects ||
            filteredUpstreamRows != upstreamSessions ||
            filteredProjectScopedSessions != projectScopedSessions ||
            filteredProjectScopedSessionErrors != projectScopedSessionErrors ||
            filteredResolvedProjectSessionScopeIDs != resolvedProjectSessionScopeIDs
        else { return }
        if projects != nextProjects {
            projects = nextProjects
        }
        if filteredUpstreamRows != upstreamSessions {
            upstreamSessions = filteredUpstreamRows
        }
        if filteredProjectScopedSessions != projectScopedSessions {
            projectScopedSessions = filteredProjectScopedSessions
        }
        if filteredProjectScopedSessionErrors != projectScopedSessionErrors {
            projectScopedSessionErrors = filteredProjectScopedSessionErrors
        }
        if filteredResolvedProjectSessionScopeIDs != resolvedProjectSessionScopeIDs {
            resolvedProjectSessionScopeIDs = filteredResolvedProjectSessionScopeIDs
        }
    }

    private func setUpstreamSessionsIfChanged(_ nextRows: [SessionLinkedUpstreamSession]) {
        guard upstreamSessions != nextRows else { return }
        upstreamSessions = nextRows
    }

    private var shouldDelayInitialPolling: Bool {
        guard !sessions.isEmpty else { return false }
        guard let lastPrimarySessionLoadAt else { return false }
        return Date().timeIntervalSince1970 - lastPrimarySessionLoadAt < 5
    }

    private var shouldHydrateProjectScopedSessionsForLists: Bool {
        projectSessionsLoader != nil && recentCatalogSessionsLoader == nil
    }

    private var shouldLoadGlobalUpstreamState: Bool {
        upstreamSessionsLoader != nil &&
            projectSessionsLoader == nil &&
            recentCatalogSessionsLoader == nil
    }

    func waitForPendingSupportingDataRefresh() async {
        await supportingDataTask?.value
    }

    private func scheduleSupportingDataRefresh(
        serverURLString: String,
        token: String,
        force: Bool
    ) {
        if force {
            supportingDataTask?.cancel()
        } else if supportingDataTask != nil {
            return
        }

        supportingDataTask = Task { [weak self] in
            guard let self else { return }
            defer { self.supportingDataTask = nil }
            await self.cleanupProviderBackedSessions(
                serverURLString: serverURLString,
                token: token
            )
            await self.cleanupMirroredDuplicateSessions(
                serverURLString: serverURLString,
                token: token
            )
            guard !Task.isCancelled else { return }
            await self.refreshSupportingProjectContent(
                serverURLString: serverURLString,
                token: token,
                force: force
            )
        }
    }

}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
