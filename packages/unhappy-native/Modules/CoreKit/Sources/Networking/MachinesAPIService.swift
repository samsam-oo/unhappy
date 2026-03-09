import Foundation

struct MachineSessionSpawnRPCParametersBuilder {
    func build(from request: MachineSessionSpawnServiceRequest) -> [String: RPCParameterValue] {
        var parameters: [String: RPCParameterValue] = [
            "directory": .string(request.directory),
            "machineId": .string(request.machineID)
        ]

        if let agent = request.agent {
            parameters["agent"] = .string(agent.rawValue)
        }
        if let codexResumeThreadID = normalized(request.codexResumeThreadID) {
            parameters["codexResumeThreadId"] = .string(codexResumeThreadID)
        }
        if let claudeResumeSessionID = normalized(request.claudeResumeSessionID) {
            parameters["claudeResumeSessionId"] = .string(claudeResumeSessionID)
        }
        if let approvedNewDirectoryCreation = request.approvedNewDirectoryCreation {
            parameters["approvedNewDirectoryCreation"] = .bool(approvedNewDirectoryCreation)
        }
        if let sessionToken = normalized(request.sessionToken) {
            parameters["token"] = .string(sessionToken)
        }
        if let environmentVariables = request.environmentVariables {
            parameters["environmentVariables"] = .object(
                environmentVariables.mapValues(RPCParameterValue.string)
            )
        }
        if let model = normalized(request.model) {
            parameters["model"] = .string(model)
        }
        if let reasoningEffort = request.reasoningEffort {
            parameters["reasoningEffort"] = .string(reasoningEffort.rawValue)
        }

        return parameters
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum MachineSessionSpawnRPCResponseParser {
    static func parse(_ data: Data) throws -> APISessionSpawnResult {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MachinesAPIError.invalidRPCPayload
        }

        if let payloadType = payload["type"] as? String {
            if payloadType == "requestToApproveDirectoryCreation" {
                return APISessionSpawnResult(
                    success: false,
                    sessionID: nil,
                    requiresUserApproval: true,
                    actionRequired: "CREATE_DIRECTORY",
                    directory: payload["directory"] as? String,
                    error: nil
                )
            }
            if payloadType == "success", let sessionID = payload["sessionId"] as? String {
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
}

extension URLSessionMachinesService {
    public func fetchProjects(
        serverURL: URL,
        token: String,
        machineID: String,
        explicitOnly: Bool = false,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> [APIMachineProjectSummary] {
        try await rpcDirectoryService.fetchProjects(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            explicitOnly: explicitOnly,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey
        )
    }

    public func openProject(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APIMachineCommandResult {
        try await rpcDirectoryService.openProject(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            path: path,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey
        )
    }

    public func removeProject(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APIMachineCommandResult {
        try await rpcDirectoryService.removeProject(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            path: path,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey
        )
    }

    public func fetchMachines(serverURL: URL, token: String) async throws -> [APIMachine] {
        let request = try MachinesAPI.makeListRequest(serverURL: serverURL, token: token)
        let (data, http) = try await httpClient.data(for: request)
        guard (200..<300).contains(http.statusCode) else {
            throw MachinesAPIError.invalidHTTPStatus(http.statusCode)
        }

        return try MachinesAPI.decodeListResponse(data)
    }

    public func spawnSession(_ request: MachineSessionSpawnServiceRequest) async throws -> APISessionSpawnResult {
        let normalizedMachineID = request.machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }
        let normalizedDirectory = request.directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDirectory.isEmpty else {
            throw MachinesAPIError.missingDirectory
        }
        let normalizedRequest = MachineSessionSpawnServiceRequest(
            serverURL: request.serverURL,
            token: request.token,
            machineID: normalizedMachineID,
            wrappedMachineDataEncryptionKey: request.wrappedMachineDataEncryptionKey,
            directory: normalizedDirectory,
            agent: request.agent,
            codexResumeThreadID: request.codexResumeThreadID,
            claudeResumeSessionID: request.claudeResumeSessionID,
            approvedNewDirectoryCreation: request.approvedNewDirectoryCreation,
            sessionToken: request.sessionToken,
            environmentVariables: request.environmentVariables,
            model: request.model,
            reasoningEffort: request.reasoningEffort
        )

        return try await rpcDirectoryService.spawnProviderSession(normalizedRequest)
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
            let (data, http) = try await httpClient.data(for: request)
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
            params: ["agent": .string(agent.rawValue)]
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
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APIMachineListDirectoryResult {
        return try await rpcDirectoryService.listDirectory(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            path: path,
            machineDataEncryptionKey: wrappedMachineDataEncryptionKey
        )
    }

    public func readFile(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APISessionReadFileResult {
        try await rpcDirectoryService.readFile(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            path: path,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey
        )
    }

    public func runBash(
        serverURL: URL,
        token: String,
        machineID: String,
        command: String,
        cwd: String,
        wrappedMachineDataEncryptionKey: String?,
        timeoutMilliseconds: Int
    ) async throws -> APISessionBashResult {
        try await rpcDirectoryService.runBash(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            command: command,
            cwd: cwd,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            timeoutMilliseconds: timeoutMilliseconds
        )
    }

    public func fetchCodexThreads(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
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
                wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
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

    public func fetchCodexThreadMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        threadID: String,
        transcriptPath: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> [APISessionMessage] {
        try await rpcDirectoryService.fetchCodexThreadMessages(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            threadID: threadID,
            transcriptPath: transcriptPath,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey
        )
    }

    public func sendCodexThreadMessage(
        serverURL: URL,
        token: String,
        machineID: String,
        threadID: String,
        cwd: String,
        transcriptPath: String?,
        wrappedMachineDataEncryptionKey: String?,
        model: String?,
        reasoningEffort: APISessionReasoningEffort?,
        permissionMode: APISessionMessagePermissionMode?,
        text: String
    ) async throws -> APISessionSendMessageResult {
        try await rpcDirectoryService.sendCodexThreadMessage(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            threadID: threadID,
            cwd: cwd,
            transcriptPath: transcriptPath,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            model: model,
            reasoningEffort: reasoningEffort,
            permissionMode: permissionMode,
            text: text
        )
    }

    public func fetchClaudeSessionMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        cwd: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> [APISessionMessage] {
        try await rpcDirectoryService.fetchClaudeSessionMessages(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            sessionID: sessionID,
            cwd: cwd,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey
        )
    }

    public func sendClaudeSessionMessage(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        cwd: String,
        wrappedMachineDataEncryptionKey: String?,
        model: String?,
        reasoningEffort: APISessionReasoningEffort?,
        permissionMode: APISessionMessagePermissionMode?,
        text: String
    ) async throws -> APISessionSendMessageResult {
        try await rpcDirectoryService.sendClaudeSessionMessage(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            sessionID: sessionID,
            cwd: cwd,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            model: model,
            reasoningEffort: reasoningEffort,
            permissionMode: permissionMode,
            text: text
        )
    }

    public func fetchCodexThreadsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APICodexThreadsPage {
        return try await rpcDirectoryService.fetchCodexThreadsPage(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            limit: min(max(limit, 1), 100),
            cwd: cwd,
            cursor: cursor
        )
    }

    public func fetchClaudeSessions(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
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
                wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
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
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APIClaudeSessionsPage {
        return try await rpcDirectoryService.fetchClaudeSessionsPage(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            limit: min(max(limit, 1), 100),
            cwd: cwd,
            cursor: cursor
        )
    }

    public func fetchGeminiSessions(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?
    ) async throws -> [APIGeminiSessionSummary] {
        let boundedLimit = min(max(limit, 1), 100)
        var cursor: String?
        var seenCursors: Set<String> = []
        var seenIDs: Set<String> = []
        var merged: [APIGeminiSessionSummary] = []

        for _ in 0..<50 {
            let page = try await fetchGeminiSessionsPage(
                serverURL: serverURL,
                token: token,
                machineID: machineID,
                wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
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

    public func fetchGeminiSessionsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APIGeminiSessionsPage {
        return try await rpcDirectoryService.fetchGeminiSessionsPage(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            limit: min(max(limit, 1), 100),
            cwd: cwd,
            cursor: cursor
        )
    }

    public func fetchGeminiSessionMessages(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> [APISessionMessage] {
        try await rpcDirectoryService.fetchGeminiSessionMessages(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            sessionID: sessionID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey
        )
    }

    public func sendGeminiSessionMessage(
        serverURL: URL,
        token: String,
        machineID: String,
        sessionID: String,
        wrappedMachineDataEncryptionKey: String?,
        model: String?,
        permissionMode: APISessionMessagePermissionMode?,
        text: String
    ) async throws -> APISessionSendMessageResult {
        try await rpcDirectoryService.sendGeminiSessionMessage(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            sessionID: sessionID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            model: model,
            permissionMode: permissionMode,
            text: text
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
