import Foundation

extension URLSessionSessionsService {
    public func fetchSessions(serverURL: URL, token: String) async throws -> [APISession] {
        let page = try await fetchSessionsPage(
            serverURL: serverURL,
            token: token,
            cursor: nil,
            limit: 50
        )
        return page.sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func fetchSessionsPage(
        serverURL: URL,
        token: String,
        cursor: String?,
        limit: Int
    ) async throws -> APISessionsPage {
        let request = try SessionsAPI.makePagedListRequest(
            serverURL: serverURL,
            token: token,
            cursor: cursor,
            limit: limit
        )
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SessionsAPIError.invalidHTTPStatus(http.statusCode)
        }

        return try SessionsAPI.decodePagedListResponse(data)
    }

    public func fetchSessionMessages(serverURL: URL, token: String, sessionID: String) async throws -> [APISessionMessage] {
        let request = try SessionsAPI.makeMessagesRequest(
            serverURL: serverURL,
            token: token,
            sessionID: sessionID
        )
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SessionsAPIError.invalidHTTPStatus(http.statusCode)
        }

        return try SessionsAPI.decodeMessagesResponse(data)
    }

    public func deleteSession(serverURL: URL, token: String, sessionID: String) async throws {
        let request = try SessionsAPI.makeDeleteRequest(
            serverURL: serverURL,
            token: token,
            sessionID: sessionID
        )
        let (_, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 404 {
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SessionsAPIError.invalidHTTPStatus(http.statusCode)
        }
    }

    public func setSessionTitle(serverURL: URL, token: String, sessionID: String, title: String?) async throws {
        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let persistedTitle: String? = normalizedTitle?.isEmpty == true ? nil : normalizedTitle

        if let persistedTitle {
            let codexRequest = try SessionsAPI.makeSetCodexTitleRequest(
                serverURL: serverURL,
                token: token,
                sessionID: sessionID,
                name: persistedTitle
            )
            let (_, codexResponse) = try await URLSession.shared.data(for: codexRequest)

            guard let codexHTTP = codexResponse as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            if (200..<300).contains(codexHTTP.statusCode) {
                return
            }

            // Some environments still return 5xx for codex-title updates even when legacy title
            // updates succeed. Fall back once to avoid surfacing transient server incompatibilities.
            let legacyFallbackRequest = try SessionsAPI.makeSetTitleRequest(
                serverURL: serverURL,
                token: token,
                sessionID: sessionID,
                title: persistedTitle
            )
            let (_, legacyFallbackResponse) = try await URLSession.shared.data(for: legacyFallbackRequest)

            guard let legacyFallbackHTTP = legacyFallbackResponse as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard (200..<300).contains(legacyFallbackHTTP.statusCode) else {
                throw SessionsAPIError.invalidHTTPStatus(codexHTTP.statusCode)
            }
            return
        }

        let legacyRequest = try SessionsAPI.makeSetTitleRequest(
            serverURL: serverURL,
            token: token,
            sessionID: sessionID,
            title: persistedTitle
        )
        let (_, legacyResponse) = try await URLSession.shared.data(for: legacyRequest)

        guard let legacyHTTP = legacyResponse as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(legacyHTTP.statusCode) else {
            throw SessionsAPIError.invalidHTTPStatus(legacyHTTP.statusCode)
        }
    }

    public func spawnSession(
        serverURL: URL,
        token: String,
        sessionID: String,
        directory: String,
        agent: APISessionSpawnAgent?,
        codexResumeThreadID: String?,
        claudeResumeSessionID: String?,
        approvedNewDirectoryCreation: Bool?
    ) async throws -> APISessionSpawnResult {
        let normalizedDirectory = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDirectory.isEmpty else {
            throw SessionsAPIError.missingDirectory
        }

        var params: [String: Any] = [
            "directory": normalizedDirectory,
        ]
        if let agent {
            params["agent"] = agent.rawValue
        }
        let normalizedCodexResumeThreadID = codexResumeThreadID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCodexResumeThreadID, !normalizedCodexResumeThreadID.isEmpty {
            params["codexResumeThreadId"] = normalizedCodexResumeThreadID
        }
        let normalizedClaudeResumeSessionID = claudeResumeSessionID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedClaudeResumeSessionID, !normalizedClaudeResumeSessionID.isEmpty {
            params["claudeResumeSessionId"] = normalizedClaudeResumeSessionID
        }
        if let approvedNewDirectoryCreation {
            params["approvedNewDirectoryCreation"] = approvedNewDirectoryCreation
        }

        let data = try await rpcCommandService.invokeCommand(
            serverURL: serverURL,
            token: token,
            sessionID: sessionID,
            command: "spawn-unhappy-session",
            params: params,
            allowMachineFallback: false
        )
        return try SessionsAPI.decodeSpawnSessionResponse(data)
    }

    public func abortSessionTask(
        serverURL: URL,
        token: String,
        sessionID: String,
        reason: String?
    ) async throws -> APISessionCommandResult {
        var params: [String: Any] = [:]
        let normalizedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedReason, !normalizedReason.isEmpty {
            params["reason"] = normalizedReason
        }
        let data = try await rpcCommandService.invokeCommand(
            serverURL: serverURL,
            token: token,
            sessionID: sessionID,
            command: "abort",
            params: params,
            allowMachineFallback: false
        )
        return try SessionsAPI.decodeSessionCommandResponse(data)
    }

    public func respondPermission(
        serverURL: URL,
        token: String,
        sessionID: String,
        permissionRequestID: String,
        approved: Bool,
        mode: APISessionPermissionMode?,
        allowTools: [String]?,
        decision: APISessionPermissionDecision?
    ) async throws -> APISessionCommandResult {
        let normalizedPermissionRequestID = permissionRequestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPermissionRequestID.isEmpty else {
            throw SessionsAPIError.missingPermissionRequestID
        }

        let normalizedAllowTools = allowTools?.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        var params: [String: Any] = [
            "id": normalizedPermissionRequestID,
            "approved": approved,
        ]
        if let mode {
            params["mode"] = mode.rawValue
        }
        if let normalizedAllowTools, !normalizedAllowTools.isEmpty {
            params["allowTools"] = normalizedAllowTools
        }
        if let decision {
            params["decision"] = decision.rawValue
        }

        let data = try await rpcCommandService.invokeCommand(
            serverURL: serverURL,
            token: token,
            sessionID: sessionID,
            command: "permission",
            params: params,
            allowMachineFallback: false
        )
        return try SessionsAPI.decodeSessionCommandResponse(data)
    }

    public func switchSessionMode(
        serverURL: URL,
        token: String,
        sessionID: String,
        to: APISessionSwitchTarget
    ) async throws -> APISessionSwitchResult {
        let data = try await rpcCommandService.invokeCommand(
            serverURL: serverURL,
            token: token,
            sessionID: sessionID,
            command: "switch",
            params: ["to": to.rawValue],
            allowMachineFallback: false
        )
        return try SessionsAPI.decodeSessionSwitchResponse(data)
    }

    public func sendMessage(
        serverURL: URL,
        token: String,
        sessionID: String,
        text: String,
        imageDataURLs: [String],
        steerMode: APISessionSteerMode?,
        permissionMode: APISessionMessagePermissionMode?,
        model: String?,
        resetModel: Bool,
        reasoningEffort: APISessionReasoningEffort?,
        resetReasoningEffort: Bool
    ) async throws -> APISessionSendMessageResult {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedImageDataURLs = imageDataURLs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedText.isEmpty || !normalizedImageDataURLs.isEmpty else {
            throw SessionsAPIError.missingMessageText
        }

        var params: [String: Any] = [:]
        if !normalizedText.isEmpty {
            params["text"] = normalizedText
        }
        if !normalizedImageDataURLs.isEmpty {
            params["images"] = normalizedImageDataURLs
        }
        if let steerMode {
            params["steerMode"] = steerMode.rawValue
        }
        if let permissionMode {
            params["permissionMode"] = permissionMode.rawValue
        }
        if resetModel {
            params["model"] = NSNull()
        } else if let model {
            let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedModel.isEmpty {
                params["model"] = normalizedModel
            }
        }
        if resetReasoningEffort {
            params["effort"] = NSNull()
        } else if let reasoningEffort {
            params["effort"] = reasoningEffort.rawValue
        }

        let data = try await rpcCommandService.invokeCommand(
            serverURL: serverURL,
            token: token,
            sessionID: sessionID,
            command: "sendMessage",
            params: params,
            allowMachineFallback: false
        )
        return try SessionsAPI.decodeSessionSendMessageResponse(data)
    }

    public func runBash(
        serverURL: URL,
        token: String,
        sessionID: String,
        command: String,
        cwd: String?,
        timeout: Int?
    ) async throws -> APISessionBashResult {
        let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCommand.isEmpty else {
            throw SessionsAPIError.missingCommand
        }

        var params: [String: Any] = [
            "command": normalizedCommand,
        ]
        let normalizedCWD = cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCWD, !normalizedCWD.isEmpty {
            params["cwd"] = normalizedCWD
        }
        if let timeout {
            params["timeout"] = timeout
        }

        let data = try await rpcCommandService.invokeCommand(
            serverURL: serverURL,
            token: token,
            sessionID: sessionID,
            command: "bash",
            params: params,
            allowMachineFallback: false
        )
        return try SessionsAPI.decodeSessionBashResponse(data)
    }

    public func runRipgrep(
        serverURL: URL,
        token: String,
        sessionID: String,
        args: [String],
        cwd: String?
    ) async throws -> APISessionBashResult {
        let normalizedArgs = args.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard !normalizedArgs.isEmpty else {
            throw SessionsAPIError.missingCommand
        }

        var params: [String: Any] = [
            "args": normalizedArgs,
        ]
        let normalizedCWD = cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCWD, !normalizedCWD.isEmpty {
            params["cwd"] = normalizedCWD
        }

        let data = try await rpcCommandService.invokeCommand(
            serverURL: serverURL,
            token: token,
            sessionID: sessionID,
            command: "ripgrep",
            params: params,
            allowMachineFallback: false
        )
        return try SessionsAPI.decodeSessionRipgrepResponse(data)
    }

    public func runDifftastic(
        serverURL: URL,
        token: String,
        sessionID: String,
        args: [String],
        cwd: String?
    ) async throws -> APISessionBashResult {
        let normalizedArgs = args.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard !normalizedArgs.isEmpty else {
            throw SessionsAPIError.missingCommand
        }

        var params: [String: Any] = [
            "args": normalizedArgs,
        ]
        let normalizedCWD = cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCWD, !normalizedCWD.isEmpty {
            params["cwd"] = normalizedCWD
        }

        let data = try await rpcCommandService.invokeCommand(
            serverURL: serverURL,
            token: token,
            sessionID: sessionID,
            command: "difftastic",
            params: params,
            allowMachineFallback: false
        )
        return try SessionsAPI.decodeSessionDifftasticResponse(data)
    }

    public func readFile(
        serverURL: URL,
        token: String,
        sessionID: String,
        path: String
    ) async throws -> APISessionReadFileResult {
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw SessionsAPIError.missingPath
        }

        let data = try await rpcCommandService.invokeCommand(
            serverURL: serverURL,
            token: token,
            sessionID: sessionID,
            command: "readFile",
            params: ["path": normalizedPath],
            allowMachineFallback: false
        )
        return try SessionsAPI.decodeSessionReadFileResponse(data)
    }

    public func writeFile(
        serverURL: URL,
        token: String,
        sessionID: String,
        path: String,
        content: String,
        expectedHash: String?
    ) async throws -> APISessionWriteFileResult {
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw SessionsAPIError.missingPath
        }
        guard !content.isEmpty else {
            throw SessionsAPIError.missingFileContent
        }

        var params: [String: Any] = [
            "path": normalizedPath,
            "content": content,
        ]
        let normalizedExpectedHash = expectedHash?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedExpectedHash, !normalizedExpectedHash.isEmpty {
            params["expectedHash"] = normalizedExpectedHash
        }

        let data = try await rpcCommandService.invokeCommand(
            serverURL: serverURL,
            token: token,
            sessionID: sessionID,
            command: "writeFile",
            params: params,
            allowMachineFallback: false
        )
        return try SessionsAPI.decodeSessionWriteFileResponse(data)
    }

    public func listDirectory(
        serverURL: URL,
        token: String,
        sessionID: String,
        path: String
    ) async throws -> APISessionListDirectoryResult {
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw SessionsAPIError.missingPath
        }

        let data = try await rpcCommandService.invokeCommand(
            serverURL: serverURL,
            token: token,
            sessionID: sessionID,
            command: "listDirectory",
            params: [
                "path": normalizedPath,
                "includeStats": true,
                "types": ["file", "directory"],
                "sort": true,
                "maxEntries": 300,
            ],
            allowMachineFallback: false
        )
        return try SessionsAPI.decodeSessionListDirectoryResponse(data)
    }

    public func killSession(
        serverURL: URL,
        token: String,
        sessionID: String
    ) async throws -> APISessionKillResult {
        let data = try await rpcCommandService.invokeCommand(
            serverURL: serverURL,
            token: token,
            sessionID: sessionID,
            command: "killSession",
            params: [:],
            allowMachineFallback: true
        )
        return try SessionsAPI.decodeSessionKillResponse(data)
    }

    public func fetchAgentCapabilities(
        serverURL: URL,
        token: String,
        sessionID: String,
        agent: APISessionSpawnAgent?
    ) async throws -> APIMachineAgentCapabilities {
        var params: [String: Any] = [:]
        if let agent {
            params["agent"] = agent.rawValue
        }
        let data = try await rpcCommandService.invokeCommand(
            serverURL: serverURL,
            token: token,
            sessionID: sessionID,
            command: "list-models",
            params: params,
            allowMachineFallback: false
        )
        return try MachinesAPI.decodeAgentCapabilitiesResponse(data)
    }
}
