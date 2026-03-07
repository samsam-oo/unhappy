import SwiftUI
import CoreKit
import FeatureSessionTools

extension SessionDetailView {
    var currentSession: APISession {
        viewModel.sessions.first(where: { $0.id == session.id }) ?? session
    }

    var currentSessionDisplayTitle: String? {
        SessionDisplayTitleResolver.resolvedDisplayTitle(
            for: currentSession,
            context: currentSessionContext
        )
    }

    var currentSessionHasDisplayTitle: Bool {
        currentSessionDisplayTitle != nil
    }

    var currentSessionTitle: String {
        if let currentSessionDisplayTitle {
            return currentSessionDisplayTitle
        }
        return SessionDisplayTitleResolver.fallbackTitle(for: currentSession)
    }

    var subAgentInProgressCount: Int {
        guard currentSession.active else { return 0 }
        return collabInProgressCountFromAgentState
    }

    var pendingPermissionRequests: [PendingPermissionRequest] {
        let sources = [decodedSessionAgentState, decodedSessionMetadata]
        let requestMap = SessionPayloadValueResolver.firstDictionary(
            in: sources,
            keys: [
                "requests",
                "pendingRequests",
                "approvalRequestMap",
                "permissionRequestMap",
            ]
        ) ?? [:]

        var rows: [PendingPermissionRequest] = []
        rows.reserveCapacity(requestMap.count)
        for (rawRequestID, rawValue) in requestMap {
            let requestID = rawRequestID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !requestID.isEmpty else { continue }
            guard let requestPayload = rawValue as? [String: Any] else {
                rows.append(
                    PendingPermissionRequest(
                        id: requestID,
                        callID: requestID,
                        toolName: "Tool",
                        summary: nil
                    )
                )
                continue
            }

            let callID = SessionPayloadValueResolver.firstString(
                in: [requestPayload],
                keys: ["callId", "toolCallId", "id"]
            ) ?? requestID
            let toolName = SessionPayloadValueResolver.firstString(
                in: [requestPayload],
                keys: ["toolName", "tool", "name"]
            ) ?? "Tool"
            let summary = permissionSummary(from: requestPayload)
            rows.append(
                PendingPermissionRequest(
                    id: requestID,
                    callID: callID,
                    toolName: toolName,
                    summary: summary
                )
            )
        }

        return rows.sorted { lhs, rhs in
            lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
    }

    var resumeDirectoryForDisconnectedSession: String? {
        currentSessionContext.workingDirectory
    }

    var upstreamAgentSessionIDForResume: String? {
        currentSessionContext.upstreamSessionID
    }

    var canAutoResumeDisconnectedSession: Bool {
        guard parsedSessionAgent != nil else { return false }
        guard resumeDirectoryForDisconnectedSession != nil else { return false }
        if parsedSessionAgent == .codex || parsedSessionAgent == .claude {
            return upstreamAgentSessionIDForResume != nil
        }
        return true
    }

    func permissionSummary(from requestPayload: [String: Any]) -> String? {
        if let summary = SessionPayloadValueResolver.firstString(
            in: [requestPayload],
            keys: ["reason", "message", "description", "prompt"]
        ) {
            let normalized = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                return clippedSummary(normalized)
            }
        }

        if let input = SessionPayloadValueResolver.firstDictionary(
            in: [requestPayload],
            keys: ["input", "arguments", "args", "payload"]
        ) {
            if let command = SessionPayloadValueResolver.firstString(
                in: [input],
                keys: ["cmd", "command", "query", "q", "url", "path"]
            ) {
                return clippedSummary(command)
            }
            if JSONSerialization.isValidJSONObject(input),
               let data = try? JSONSerialization.data(withJSONObject: input, options: []),
               let text = String(data: data, encoding: .utf8) {
                return clippedSummary(text)
            }
        }

        return nil
    }

    func clippedSummary(_ raw: String, limit: Int = 180) -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)) + "…"
    }

    func respondToPermissionRequest(
        _ requestID: String,
        approved: Bool
    ) {
        guard respondingPermissionRequestID == nil else { return }
        let normalizedRequestID = requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRequestID.isEmpty else { return }

        respondingPermissionRequestID = normalizedRequestID
        permissionActionStatusMessage = nil
        permissionActionErrorMessage = nil

        let currentSessionID = currentSession.id
        Task {
            let toolsViewModel = makeSessionToolsViewModel()
            toolsViewModel.permissionRequestID = normalizedRequestID
            toolsViewModel.permissionDecision = approved ? .approvedForSession : .denied
            toolsViewModel.permissionMode = .default
            toolsViewModel.permissionAllowTools = ""
            await toolsViewModel.submitPermissionDecision(
                sessionID: currentSessionID,
                serverURLString: serverURLString,
                token: token
            )

            let actionError = toolsViewModel.permissionErrorMessage?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let actionError, !actionError.isEmpty {
                respondingPermissionRequestID = nil
                permissionActionStatusMessage = nil
                if actionError.lowercased().contains("session rpc is not connected") {
                    if canAutoResumeDisconnectedSession {
                        isRecoveringDisconnectedSession = true
                        let resumedSessionID = await recoverDisconnectedSessionForApproval()
                        isRecoveringDisconnectedSession = false
                        if let resumedSessionID, !resumedSessionID.isEmpty {
                            permissionActionErrorMessage = nil
                            permissionActionStatusMessage =
                                "Session resumed into \(resumedSessionID). Open it and retry approval."
                        } else {
                            permissionActionErrorMessage =
                                "Session is disconnected. Failed to auto-resume. Resume it manually, then retry approval."
                        }
                    } else {
                        permissionActionErrorMessage =
                            "Session is disconnected. Resume or reopen this session, then try approval again."
                    }
                } else {
                    permissionActionErrorMessage = actionError
                }
                return
            }

            respondingPermissionRequestID = nil
            permissionActionErrorMessage = nil
            permissionActionStatusMessage = approved ? "Approved permission request" : "Denied permission request"

            await viewModel.load(
                serverURLString: serverURLString,
                token: token
            )
            await viewModel.loadMessages(
                for: currentSessionID,
                serverURLString: serverURLString,
                token: token
            )
        }
    }

    func recoverDisconnectedSessionForApproval() async -> String? {
        guard let agent = parsedSessionAgent else {
            return nil
        }
        guard let directory = resumeDirectoryForDisconnectedSession else {
            return nil
        }

        let upstreamSessionID = upstreamAgentSessionIDForResume
        let codexResumeThreadID = agent == .codex ? upstreamSessionID : nil
        let claudeResumeSessionID = agent == .claude ? upstreamSessionID : nil
        if agent == .codex && (codexResumeThreadID == nil || codexResumeThreadID?.isEmpty == true) {
            return nil
        }
        if agent == .claude && (claudeResumeSessionID == nil || claudeResumeSessionID?.isEmpty == true) {
            return nil
        }

        let spawnUseCase = SessionSpawnUseCase(service: URLSessionSessionsService())
        do {
            let response = try await spawnUseCase.spawnSession(
                SessionSpawnRequest(
                    serverURLString: serverURLString,
                    token: token,
                    sessionID: currentSession.id,
                    directory: directory,
                    agent: agent,
                    codexResumeThreadID: codexResumeThreadID,
                    claudeResumeSessionID: claudeResumeSessionID,
                    approvedNewDirectoryCreation: true
                )
            )
            await viewModel.load(
                serverURLString: serverURLString,
                token: token
            )
            return response.sessionID
        } catch {
            return nil
        }
    }
}
