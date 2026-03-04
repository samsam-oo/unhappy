import Foundation

extension URLSessionMachinesService {
    public func fetchMachines(serverURL: URL, token: String) async throws -> [APIMachine] {
        let request = try MachinesAPI.makeListRequest(serverURL: serverURL, token: token)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MachinesAPIError.invalidHTTPStatus(http.statusCode)
        }

        return try MachinesAPI.decodeListResponse(data)
    }

    public func spawnSession(
        serverURL: URL,
        token: String,
        machineID: String,
        directory: String,
        agent: APISessionSpawnAgent?,
        codexResumeThreadID: String?,
        claudeResumeSessionID: String?,
        approvedNewDirectoryCreation: Bool?,
        sessionToken: String?,
        environmentVariables: [String: String]?,
        model: String?,
        reasoningEffort: APISessionReasoningEffort?
    ) async throws -> APISessionSpawnResult {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let normalizedDirectory = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDirectory.isEmpty else {
            throw MachinesAPIError.missingDirectory
        }

        do {
            let request = try MachinesAPI.makeSpawnSessionRequest(
                serverURL: serverURL,
                token: token,
                machineID: normalizedMachineID,
                directory: normalizedDirectory,
                agent: agent,
                codexResumeThreadID: codexResumeThreadID,
                claudeResumeSessionID: claudeResumeSessionID,
                approvedNewDirectoryCreation: approvedNewDirectoryCreation,
                sessionToken: sessionToken,
                environmentVariables: environmentVariables,
                model: model,
                reasoningEffort: reasoningEffort
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            if (200..<300).contains(http.statusCode) || http.statusCode == 409 {
                return try MachinesAPI.decodeSpawnResponse(data)
            }
            if shouldFallbackToRPC(statusCode: http.statusCode) {
                throw MachinesAPIError.endpointUnavailable("/v1/machines/:id/spawn")
            }
            let errorMessage = parseServerErrorMessage(from: data)
            if let errorMessage {
                throw MachinesAPIError.rpcCallFailed(errorMessage)
            }
            throw MachinesAPIError.invalidHTTPStatus(http.statusCode)
        } catch let error as MachinesAPIError {
            if case .endpointUnavailable = error {
                // Fallback for older backends that do not yet expose REST machine commands.
            } else {
                throw error
            }
        }

        var params: [String: Any] = [
            "directory": normalizedDirectory,
            "machineId": normalizedMachineID,
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
        let normalizedSessionToken = sessionToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedSessionToken, !normalizedSessionToken.isEmpty {
            params["token"] = normalizedSessionToken
        }
        if let environmentVariables {
            params["environmentVariables"] = environmentVariables
        }
        let normalizedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedModel, !normalizedModel.isEmpty {
            params["model"] = normalizedModel
        }
        if let reasoningEffort {
            params["reasoningEffort"] = reasoningEffort.rawValue
        }

        let data = try await rpcDirectoryService.invokeCommand(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            command: "spawn-unhappy-session",
            params: params
        )

        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MachinesAPIError.invalidRPCPayload
        }

        if let type = payload["type"] as? String {
            if type == "requestToApproveDirectoryCreation" {
                return APISessionSpawnResult(
                    success: false,
                    sessionID: nil,
                    requiresUserApproval: true,
                    actionRequired: "CREATE_DIRECTORY",
                    directory: payload["directory"] as? String,
                    error: nil
                )
            }
            if type == "success", let sessionID = payload["sessionId"] as? String {
                return APISessionSpawnResult(
                    success: true,
                    sessionID: sessionID,
                    requiresUserApproval: nil,
                    actionRequired: nil,
                    directory: nil,
                    error: nil
                )
            }
        }

        if payload["success"] as? Bool == false {
            return APISessionSpawnResult(
                success: false,
                sessionID: nil,
                requiresUserApproval: nil,
                actionRequired: nil,
                directory: nil,
                error: payload["error"] as? String
            )
        }

        return APISessionSpawnResult(
            success: false,
            sessionID: nil,
            requiresUserApproval: nil,
            actionRequired: nil,
            directory: nil,
            error: (payload["error"] as? String) ?? (payload["errorMessage"] as? String) ?? "Failed to spawn session"
        )
    }

    public func fetchAgentCapabilities(
        serverURL: URL,
        token: String,
        machineID: String,
        agent: APISessionSpawnAgent
    ) async throws -> APIMachineAgentCapabilities {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }

        do {
            let request = try MachinesAPI.makeListModelsRequest(
                serverURL: serverURL,
                token: token,
                machineID: normalizedMachineID,
                agent: agent
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard (200..<300).contains(http.statusCode) else {
                if shouldFallbackToRPC(statusCode: http.statusCode) {
                    throw MachinesAPIError.endpointUnavailable("/v1/machines/:id/models")
                }
                let errorMessage = parseServerErrorMessage(from: data)
                if let errorMessage {
                    throw MachinesAPIError.rpcCallFailed(errorMessage)
                }
                throw MachinesAPIError.invalidHTTPStatus(http.statusCode)
            }
            return try MachinesAPI.decodeAgentCapabilitiesResponse(data)
        } catch let error as MachinesAPIError {
            if case .endpointUnavailable = error {
                // Fallback for servers that do not yet expose /models.
            } else {
                throw error
            }
        }

        let data = try await rpcDirectoryService.invokeCommand(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            command: "list-models",
            params: ["agent": agent.rawValue]
        )
        return try MachinesAPI.decodeAgentCapabilitiesResponse(data)
    }

    public func stopDaemon(serverURL: URL, token: String, machineID: String) async throws -> APIMachineCommandResult {
        let data = try await rpcDirectoryService.invokeCommand(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            command: "stop-daemon",
            params: [:]
        )
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MachinesAPIError.invalidRPCPayload
        }

        let success = payload["success"] as? Bool ?? false
        let normalizedError = (payload["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if !success {
            throw MachinesAPIError.rpcCallFailed(
                (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "Failed to stop daemon"
            )
        }
        let normalizedMessage = (payload["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return APIMachineCommandResult(
            success: true,
            message: (normalizedMessage?.isEmpty == false ? normalizedMessage : nil) ?? "Daemon stop request acknowledged",
            error: nil
        )
    }

    public func updateDaemon(serverURL: URL, token: String, machineID: String) async throws -> APIMachineCommandResult {
        let data = try await rpcDirectoryService.invokeCommand(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            command: "update-daemon",
            params: [:]
        )
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MachinesAPIError.invalidRPCPayload
        }

        let success = payload["success"] as? Bool ?? false
        let normalizedError = (payload["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if !success {
            throw MachinesAPIError.rpcCallFailed(
                (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "Failed to update daemon"
            )
        }
        let normalizedMessage = (payload["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return APIMachineCommandResult(
            success: true,
            message: (normalizedMessage?.isEmpty == false ? normalizedMessage : nil) ?? "Daemon update requested",
            error: nil
        )
    }

    public func listDirectory(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String
    ) async throws -> APIMachineListDirectoryResult {
        do {
            let request = try MachinesAPI.makeListDirectoryRequest(
                serverURL: serverURL,
                token: token,
                machineID: machineID,
                path: path,
                includeStats: false,
                types: ["directory"],
                sort: true,
                maxEntries: 2_000
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard (200..<300).contains(http.statusCode) else {
                if shouldFallbackToRPC(statusCode: http.statusCode) {
                    throw MachinesAPIError.endpointUnavailable("/v1/machines/:id/commands/list-directory")
                }
                let errorMessage = parseServerErrorMessage(from: data)
                if let errorMessage {
                    throw MachinesAPIError.rpcCallFailed(errorMessage)
                }
                throw MachinesAPIError.invalidHTTPStatus(http.statusCode)
            }
            return try MachinesAPI.decodeListDirectoryResponse(data)
        } catch let error as MachinesAPIError {
            if case .endpointUnavailable = error {
                // Fallback for servers that do not yet expose list-directory.
            } else {
                throw error
            }
        }

        return try await rpcDirectoryService.listDirectory(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            path: path,
            machineDataEncryptionKey: nil
        )
    }

    public func fetchCodexThreads(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?
    ) async throws -> [APICodexThreadSummary] {
        let boundedLimit = min(max(limit, 1), 100)
        var cursor: String?
        var seenCursors: Set<String> = []
        var seenIDs: Set<String> = []
        var merged: [APICodexThreadSummary] = []

        for _ in 0..<50 {
            let page = try await fetchCodexThreadsPage(
                serverURL: serverURL,
                token: token,
                machineID: machineID,
                limit: boundedLimit,
                cwd: cwd,
                cursor: cursor
            )
            for row in page.threads where seenIDs.insert(row.id).inserted {
                merged.append(row)
            }

            guard page.hasNext, let nextCursor = page.nextCursor else {
                break
            }
            guard seenCursors.insert(nextCursor).inserted else {
                break
            }
            cursor = nextCursor
        }

        return merged
    }

    public func fetchCodexThreadsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APICodexThreadsPage {
        let boundedLimit = min(max(limit, 1), 100)
        do {
            let request = try MachinesAPI.makeCodexThreadsRequest(
                serverURL: serverURL,
                token: token,
                machineID: machineID,
                limit: boundedLimit,
                cwd: cwd,
                cursor: cursor
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard (200..<300).contains(http.statusCode) else {
                if shouldFallbackToRPC(statusCode: http.statusCode) {
                    throw MachinesAPIError.endpointUnavailable("/v1/machines/:id/codex/threads")
                }
                let errorMessage = parseServerErrorMessage(from: data)
                if let errorMessage {
                    throw MachinesAPIError.rpcCallFailed(errorMessage)
                }
                throw MachinesAPIError.invalidHTTPStatus(http.statusCode)
            }
            return try MachinesAPI.decodeCodexThreadsPageResponse(data)
        } catch let error as MachinesAPIError {
            if case .endpointUnavailable = error {
                // Fallback for servers that do not yet expose codex thread listing.
            } else {
                throw error
            }
        }

        return try await rpcDirectoryService.fetchCodexThreadsPage(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            limit: boundedLimit,
            cwd: cwd,
            cursor: cursor
        )
    }

    public func fetchClaudeSessions(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?
    ) async throws -> [APIClaudeSessionSummary] {
        let boundedLimit = min(max(limit, 1), 100)
        var cursor: String?
        var seenCursors: Set<String> = []
        var seenIDs: Set<String> = []
        var merged: [APIClaudeSessionSummary] = []

        for _ in 0..<50 {
            let page = try await fetchClaudeSessionsPage(
                serverURL: serverURL,
                token: token,
                machineID: machineID,
                limit: boundedLimit,
                cwd: cwd,
                cursor: cursor
            )
            for row in page.sessions where seenIDs.insert(row.id).inserted {
                merged.append(row)
            }

            guard page.hasNext, let nextCursor = page.nextCursor else {
                break
            }
            guard seenCursors.insert(nextCursor).inserted else {
                break
            }
            cursor = nextCursor
        }

        return merged
    }

    public func fetchClaudeSessionsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APIClaudeSessionsPage {
        let boundedLimit = min(max(limit, 1), 100)
        do {
            let request = try MachinesAPI.makeClaudeSessionsRequest(
                serverURL: serverURL,
                token: token,
                machineID: machineID,
                limit: boundedLimit,
                cwd: cwd,
                cursor: cursor
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard (200..<300).contains(http.statusCode) else {
                if shouldFallbackToRPC(statusCode: http.statusCode) {
                    throw MachinesAPIError.endpointUnavailable("/v1/machines/:id/claude/sessions")
                }
                let errorMessage = parseServerErrorMessage(from: data)
                if let errorMessage {
                    throw MachinesAPIError.rpcCallFailed(errorMessage)
                }
                throw MachinesAPIError.invalidHTTPStatus(http.statusCode)
            }
            return try MachinesAPI.decodeClaudeSessionsPageResponse(data)
        } catch let error as MachinesAPIError {
            if case .endpointUnavailable = error {
                // Fallback for servers that do not yet expose Claude session listing.
            } else {
                throw error
            }
        }

        return try await rpcDirectoryService.fetchClaudeSessionsPage(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            limit: boundedLimit,
            cwd: cwd,
            cursor: cursor
        )
    }

    private func shouldFallbackToRPC(statusCode: Int) -> Bool {
        statusCode == 404 || statusCode == 405 || statusCode == 501
    }

    private func parseServerErrorMessage(from data: Data) -> String? {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let keys = ["error", "message", "errorMessage"]
        for key in keys {
            if let value = payload[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }
}
