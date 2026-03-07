import Foundation
import UserNotifications
import ActivityKit
import CoreKit

@MainActor
protocol SessionPresenceCoordinating {
    func start() async
    func handleSessionsChanged(_ sessions: [APISession]) async
}

struct SessionRuntimeSnapshot: Equatable, Sendable {
    let sessionID: String
    let isActive: Bool
    let title: String
    let agent: UnhappySessionAgentKind
    let directory: String
    let statusText: String
    let requiresApproval: Bool
    let updatedAt: Date

    init(session: APISession) {
        let metadata = SessionPayloadDecoder.decodeJSONObject(
            payload: session.metadata,
            dataEncryptionKey: session.dataEncryptionKey
        )
        let agentState = SessionPayloadDecoder.decodeJSONObject(
            payload: session.agentState,
            dataEncryptionKey: session.dataEncryptionKey
        )

        self.sessionID = session.id
        self.isActive = session.active
        self.title = Self.resolveTitle(session: session, metadata: metadata, agentState: agentState)
        self.agent = Self.resolveAgent(metadata: metadata, agentState: agentState)
        self.directory = Self.resolveDirectory(metadata: metadata, agentState: agentState)
        self.requiresApproval = Self.resolveRequiresApproval(metadata: metadata, agentState: agentState)
        self.statusText = Self.resolveStatusText(
            isActive: session.active,
            requiresApproval: requiresApproval,
            metadata: metadata,
            agentState: agentState
        )
        self.updatedAt = Date(timeIntervalSince1970: session.updatedAt)
    }

    private static func resolveTitle(
        session: APISession,
        metadata: [String: Any],
        agentState: [String: Any]
    ) -> String {
        if let raw = session.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           raw != session.id {
            return raw
        }

        if let summary = resolveSummaryText(from: [agentState, metadata]) {
            return summary
        }

        if let raw = SessionPayloadDecoder.firstString(
            in: [agentState, metadata],
            keys: ["displayName", "name", "title", "threadName", "sessionName"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           raw != session.id {
            return raw
        }

        if let seq = session.seq, seq > 0 {
            return "Session \(seq)"
        }
        return "Session"
    }

    private static func resolveSummaryText(from objects: [Any]) -> String? {
        for object in objects {
            if let dictionary = object as? [String: Any] {
                if let summaryObject = dictionary["summary"] as? [String: Any],
                   let text = summaryObject["text"] as? String {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
                if let summary = dictionary["summary"] as? String {
                    let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            }
        }
        return nil
    }

    private static func resolveAgent(
        metadata: [String: Any],
        agentState: [String: Any]
    ) -> UnhappySessionAgentKind {
        if let resolved = resolveAgent(
            from: metadata,
            keys: [
                "agent",
                "agentType",
                "backend",
                "provider",
                "flavor",
                "model"
            ]
        ) {
            return resolved
        }

        if let resolved = resolveAgent(
            from: agentState,
            keys: [
                "agent",
                "agentType",
                "backend",
                "provider",
                "flavor",
                "model"
            ]
        ) {
            return resolved
        }

        return .unknown
    }

    private static func resolveAgent(
        from object: [String: Any],
        keys: [String]
    ) -> UnhappySessionAgentKind? {
        let raw = SessionPayloadDecoder.firstString(in: [object], keys: keys)
        let normalized = raw?.lowercased() ?? ""
        if normalized.contains("claude") {
            return .claude
        }
        if normalized.contains("gemini") {
            return .gemini
        }
        if normalized.contains("codex") || normalized.contains("gpt") || normalized.contains("openai") {
            return .codex
        }
        return nil
    }

    private static func resolveDirectory(
        metadata: [String: Any],
        agentState: [String: Any]
    ) -> String {
        let path = SessionPayloadDecoder.firstString(
            in: [agentState, metadata],
            keys: [
                "cwd",
                "path",
                "directory",
                "workDir",
                "workingDirectory",
                "projectPath"
            ]
        )?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let path, !path.isEmpty {
            return path
        }
        return "Directory unavailable"
    }

    private static func resolveRequiresApproval(
        metadata: [String: Any],
        agentState: [String: Any]
    ) -> Bool {
        if let explicit = SessionPayloadDecoder.firstBool(
            in: [agentState, metadata],
            keys: [
                "requiresUserApproval",
                "needsApproval",
                "approvalRequired",
                "approvalPending",
                "permissionPending",
                "waitingApproval",
                "awaitingApproval"
            ]
        ) {
            return explicit
        }

        if SessionPayloadDecoder.hasNonEmptyArray(
            in: [agentState, metadata],
            keys: [
                "pendingPermissions",
                "approvalRequests",
                "permissionRequests",
                "pendingApprovalRequests"
            ]
        ) {
            return true
        }

        if SessionPayloadDecoder.hasNonEmptyDictionary(
            in: [agentState, metadata],
            keys: [
                "requests",
                "pendingRequests",
                "approvalRequestMap",
                "permissionRequestMap"
            ]
        ) {
            return true
        }

        if let status = SessionPayloadDecoder.firstString(
            in: [agentState, metadata],
            keys: ["status", "state", "phase"]
        )?.lowercased(),
           status.contains("approval") || status.contains("permission") {
            return true
        }
        return false
    }

    private static func resolveStatusText(
        isActive: Bool,
        requiresApproval: Bool,
        metadata: [String: Any],
        agentState: [String: Any]
    ) -> String {
        if requiresApproval {
            return "Approval needed"
        }

        if let statusRaw = SessionPayloadDecoder.firstString(
            in: [agentState, metadata],
            keys: ["status", "state", "phase", "activity", "mode"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
           !statusRaw.isEmpty {
            let clipped = String(statusRaw.prefix(64))
            return clipped.prefix(1).uppercased() + clipped.dropFirst()
        }

        if let isThinking = SessionPayloadDecoder.firstBool(
            in: [agentState, metadata],
            keys: ["thinking", "busy", "working", "running", "processing"]
        ), isThinking {
            return "Working"
        }

        return isActive ? "Running" : "Completed"
    }
}

protocol SessionNotificationsHandling: Sendable {
    func requestAuthorizationIfNeeded() async
    func notifySessionsCompleted(_ sessions: [SessionRuntimeSnapshot]) async
}

protocol SessionsLiveActivityHandling: Sendable {
    func startIfNeeded() async
    func syncSessions(_ activeSessions: [SessionRuntimeSnapshot]) async
}

@MainActor
final class SessionPresenceCoordinator: SessionPresenceCoordinating {
    private let notifications: any SessionNotificationsHandling
    private let liveActivity: any SessionsLiveActivityHandling
    private var started = false
    private var previousBySessionID: [String: SessionRuntimeSnapshot] = [:]

    init(
        notifications: any SessionNotificationsHandling,
        liveActivity: any SessionsLiveActivityHandling
    ) {
        self.notifications = notifications
        self.liveActivity = liveActivity
    }

    func start() async {
        guard !started else { return }
        started = true
        await notifications.requestAuthorizationIfNeeded()
        await liveActivity.startIfNeeded()
    }

    func handleSessionsChanged(_ sessions: [APISession]) async {
        let snapshots = sessions.map(SessionRuntimeSnapshot.init(session:))
        let activeSnapshots = snapshots.filter(\.isActive)
        await liveActivity.syncSessions(activeSnapshots)

        let currentBySessionID = Self.indexBySessionID(snapshots)
        defer { previousBySessionID = currentBySessionID }

        guard !previousBySessionID.isEmpty else { return }

        var completedSessions: [SessionRuntimeSnapshot] = []
        for (sessionID, previous) in previousBySessionID {
            guard previous.isActive else { continue }
            guard let current = currentBySessionID[sessionID], !current.isActive else { continue }
            completedSessions.append(current)
        }
        if !completedSessions.isEmpty {
            await notifications.notifySessionsCompleted(completedSessions)
        }
    }

    private static func indexBySessionID(
        _ snapshots: [SessionRuntimeSnapshot]
    ) -> [String: SessionRuntimeSnapshot] {
        snapshots.reduce(into: [:]) { partial, snapshot in
            partial[snapshot.sessionID] = snapshot
        }
    }
}

actor UserNotificationsSessionNotifier: SessionNotificationsHandling {
    private let center: UNUserNotificationCenter
    private var requestedAuthorization = false
    private var lastNotificationAtByKey: [String: Date] = [:]
    private let minimumDeduplicationInterval: TimeInterval = 8

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorizationIfNeeded() async {
        guard !requestedAuthorization else { return }
        requestedAuthorization = true

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func notifySessionsCompleted(_ sessions: [SessionRuntimeSnapshot]) async {
        guard !sessions.isEmpty else { return }
        let sorted = sessions.sorted { $0.updatedAt > $1.updatedAt }

        if sorted.count == 1, let session = sorted.first {
            let key = "done:\(session.sessionID)"
            guard shouldSendNotification(for: key) else { return }
            let body = "\(session.title) finished."
            await sendNotification(
                identifierPrefix: "im.unhappy.session.completed",
                title: "Session completed",
                body: body
            )
            return
        }

        let key = "done-group:\(sorted.map(\.sessionID).joined(separator: ","))"
        guard shouldSendNotification(for: key) else { return }
        await sendNotification(
            identifierPrefix: "im.unhappy.session.completed.group",
            title: "Sessions completed",
            body: "\(sorted.count) sessions finished."
        )
    }

    private func sendNotification(
        identifierPrefix: String,
        title: String,
        body: String
    ) async {
        let settings = await center.notificationSettings()
        let status = settings.authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    private func shouldSendNotification(for key: String) -> Bool {
        let now = Date()
        if let lastSent = lastNotificationAtByKey[key],
           now.timeIntervalSince(lastSent) < minimumDeduplicationInterval {
            return false
        }
        lastNotificationAtByKey[key] = now
        return true
    }
}

actor ActivityKitSessionsLiveActivityService: SessionsLiveActivityHandling {
    private var activitiesBySessionID: [String: Activity<UnhappySessionsActivityAttributes>] = [:]
    private var lastContentStateBySessionID: [String: UnhappySessionsActivityAttributes.ContentState] = [:]
    private var didLoadExistingActivities = false
    private let inactivityTimeout: TimeInterval = 90
    private let inactiveDismissDelay: TimeInterval = 20

    func startIfNeeded() async {
        guard !didLoadExistingActivities else { return }
        didLoadExistingActivities = true
        var mapped: [String: Activity<UnhappySessionsActivityAttributes>] = [:]
        for activity in Activity<UnhappySessionsActivityAttributes>.activities {
            mapped[activity.attributes.sessionID] = activity
        }
        activitiesBySessionID = mapped
    }

    func syncSessions(_ activeSessions: [SessionRuntimeSnapshot]) async {
        await startIfNeeded()

        if !ActivityAuthorizationInfo().areActivitiesEnabled {
            await endAllActivities(dismissalPolicy: .immediate)
            return
        }

        let now = Date()
        let staleActiveSessions = staleActiveSessions(from: activeSessions, now: now)
        let liveSessions = activeSessions.filter { session in
            !staleActiveSessions.contains(where: { $0.sessionID == session.sessionID })
        }

        await endInactiveActivities(staleActiveSessions, now: now)

        let activeBySessionID = liveSessions.reduce(into: [String: SessionRuntimeSnapshot]()) { partial, session in
            partial[session.sessionID] = session
        }
        let activeSessionIDs = Set(activeBySessionID.keys)
        let staleSessionIDs = Set(activitiesBySessionID.keys).subtracting(activeSessionIDs)

        await endCompletedActivities(staleSessionIDs, now: now)
        await syncLiveActivities(liveSessions)
    }

    private func staleActiveSessions(
        from activeSessions: [SessionRuntimeSnapshot],
        now: Date
    ) -> [SessionRuntimeSnapshot] {
        activeSessions.filter { session in
            guard !session.requiresApproval else { return false }
            return now.timeIntervalSince(session.updatedAt) >= inactivityTimeout
        }
    }

    private func endInactiveActivities(
        _ sessions: [SessionRuntimeSnapshot],
        now: Date
    ) async {
        for session in sessions {
            await endActivity(
                for: session.sessionID,
                endState: endContentState(
                    for: session,
                    statusText: "Inactive",
                    updatedAt: now
                ),
                dismissalPolicy: .after(now.addingTimeInterval(inactiveDismissDelay))
            )
        }
    }

    private func endCompletedActivities(
        _ staleSessionIDs: Set<String>,
        now: Date
    ) async {
        for sessionID in staleSessionIDs {
            await endActivity(
                for: sessionID,
                endState: endContentState(
                    for: nil,
                    statusText: "Completed",
                    updatedAt: now
                ),
                dismissalPolicy: .immediate
            )
        }
    }

    private func syncLiveActivities(
        _ liveSessions: [SessionRuntimeSnapshot]
    ) async {
        for activeSession in liveSessions {
            let contentState = contentState(for: activeSession)
            let previousContentState = lastContentStateBySessionID[activeSession.sessionID]

            if let activity = activitiesBySessionID[activeSession.sessionID] {
                if let previousContentState,
                   isSemanticallySame(previousContentState, contentState) {
                    continue
                }

                await updateActivity(
                    activity,
                    sessionID: activeSession.sessionID,
                    contentState: contentState
                )
                continue
            }

            await requestActivity(for: activeSession.sessionID, contentState: contentState)
        }
    }

    private func updateActivity(
        _ activity: Activity<UnhappySessionsActivityAttributes>,
        sessionID: String,
        contentState: UnhappySessionsActivityAttributes.ContentState
    ) async {
        let content = ActivityContent(
            state: contentState,
            staleDate: Date().addingTimeInterval(60 * 5)
        )
        await activity.update(content)
        lastContentStateBySessionID[sessionID] = contentState
    }

    private func requestActivity(
        for sessionID: String,
        contentState: UnhappySessionsActivityAttributes.ContentState
    ) async {
        let attributes = UnhappySessionsActivityAttributes(sessionID: sessionID)
        do {
            let content = ActivityContent(
                state: contentState,
                staleDate: Date().addingTimeInterval(60 * 5)
            )
            let activity = try Activity.request(attributes: attributes, content: content)
            activitiesBySessionID[sessionID] = activity
            lastContentStateBySessionID[sessionID] = contentState
        } catch {
            // Keep silent to avoid interrupting session UX when Live Activity is unavailable.
        }
    }

    private func contentState(
        for session: SessionRuntimeSnapshot
    ) -> UnhappySessionsActivityAttributes.ContentState {
        let previousAgent = lastContentStateBySessionID[session.sessionID]?.agent
        let stableAgent: UnhappySessionAgentKind
        if session.agent == .unknown,
           let previousAgent,
           previousAgent != .unknown {
            stableAgent = previousAgent
        } else {
            stableAgent = session.agent
        }

        return UnhappySessionsActivityAttributes.ContentState(
            title: session.title,
            agent: stableAgent,
            directory: session.directory,
            statusText: session.statusText,
            requiresApproval: session.requiresApproval,
            updatedAt: session.updatedAt
        )
    }

    private func isSemanticallySame(
        _ lhs: UnhappySessionsActivityAttributes.ContentState,
        _ rhs: UnhappySessionsActivityAttributes.ContentState
    ) -> Bool {
        lhs.title == rhs.title &&
        lhs.agent == rhs.agent &&
        lhs.directory == rhs.directory &&
        lhs.statusText == rhs.statusText &&
        lhs.requiresApproval == rhs.requiresApproval
    }

    private func endAllActivities(dismissalPolicy: ActivityUIDismissalPolicy) async {
        let sessionIDs = Array(activitiesBySessionID.keys)
        for sessionID in sessionIDs {
            await endActivity(
                for: sessionID,
                endState: endContentState(
                    for: nil,
                    statusText: "Completed",
                    updatedAt: Date()
                ),
                dismissalPolicy: dismissalPolicy
            )
        }
    }

    private func endActivity(
        for sessionID: String,
        endState: UnhappySessionsActivityAttributes.ContentState,
        dismissalPolicy: ActivityUIDismissalPolicy
    ) async {
        guard let activity = activitiesBySessionID[sessionID] else { return }
        let endContent = ActivityContent(state: endState, staleDate: nil)
        await activity.end(endContent, dismissalPolicy: dismissalPolicy)
        activitiesBySessionID[sessionID] = nil
        lastContentStateBySessionID[sessionID] = nil
    }

    private func endContentState(
        for session: SessionRuntimeSnapshot?,
        statusText: String,
        updatedAt: Date
    ) -> UnhappySessionsActivityAttributes.ContentState {
        UnhappySessionsActivityAttributes.ContentState(
            title: session?.title ?? "Session",
            agent: session?.agent ?? .unknown,
            directory: session?.directory ?? "Directory unavailable",
            statusText: statusText,
            requiresApproval: session?.requiresApproval ?? false,
            updatedAt: updatedAt
        )
    }
}
