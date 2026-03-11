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
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = ProjectsCacheKey(
            serverURLString: serverURL.absoluteString,
            token: normalizedToken,
            machineID: normalizedMachineID,
            explicitOnly: explicitOnly
        )

        if let cached = projectsCache[cacheKey],
           Date().timeIntervalSince1970 - cached.cachedAt < MachinesCachePolicy.ttl {
            return cached.projects
        }

        if let inFlightTask = inFlightProjectFetches[cacheKey] {
            return try await inFlightTask.value
        }

        let httpClient = self.httpClient
        let task = Task<[APIMachineProjectSummary], Error> {
            let request = try MachinesAPI.makeProjectCatalogProjectsRequest(
                serverURL: serverURL,
                token: normalizedToken,
                machineID: normalizedMachineID
            )
            let (data, http) = try await httpClient.data(for: request)
            guard (200..<300).contains(http.statusCode) else {
                let errorMessage = parseServerErrorMessage(from: data)
                if let errorMessage {
                    throw MachinesAPIError.rpcCallFailed(errorMessage)
                }
                throw MachinesAPIError.invalidHTTPStatus(http.statusCode)
            }
            let projects = try MachinesAPI.decodeProjectsResponse(data)
            if explicitOnly {
                return projects.filter(\.openedExplicitly)
            }
            return projects
        }

        inFlightProjectFetches[cacheKey] = task
        defer { inFlightProjectFetches[cacheKey] = nil }

        let projects = try await task.value
        projectsCache[cacheKey] = ProjectsCacheEntry(
            projects: projects,
            cachedAt: Date().timeIntervalSince1970
        )
        return projects
    }

    public func fetchProjectSessionsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        projectPath: String,
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APIProjectSessionsPage {
        let request = try MachinesAPI.makeProjectSessionsCatalogRequest(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            path: projectPath,
            limit: limit,
            cursor: cursor
        )
        let (data, http) = try await httpClient.data(for: request)
        guard (200..<300).contains(http.statusCode) else {
            let errorMessage = parseServerErrorMessage(from: data)
            if let errorMessage {
                throw MachinesAPIError.rpcCallFailed(errorMessage)
            }
            throw MachinesAPIError.invalidHTTPStatus(http.statusCode)
        }
        return try MachinesAPI.decodeProjectSessionsPageResponse(data)
    }

    public func fetchRecentSessionCatalogPage(
        serverURL: URL,
        token: String,
        limit: Int,
        cursor: String?
    ) async throws -> APIRecentCatalogSessionsPage {
        let request = try MachinesAPI.makeRecentSessionCatalogRequest(
            serverURL: serverURL,
            token: token,
            limit: limit,
            cursor: cursor
        )
        let (data, http) = try await httpClient.data(for: request)
        guard (200..<300).contains(http.statusCode) else {
            let errorMessage = parseServerErrorMessage(from: data)
            if let errorMessage {
                throw MachinesAPIError.rpcCallFailed(errorMessage)
            }
            throw MachinesAPIError.invalidHTTPStatus(http.statusCode)
        }
        return try MachinesAPI.decodeRecentCatalogSessionsPageResponse(data)
    }

    public func openProject(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APIMachineCommandResult {
        let result = try await rpcDirectoryService.openProject(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            path: path,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey
        )
        invalidateProjectCaches(
            serverURL: serverURL,
            token: token,
            machineID: machineID
        )
        return result
    }

    public func removeProject(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APIMachineCommandResult {
        let result = try await rpcDirectoryService.removeProject(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            path: path,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey
        )
        invalidateProjectCaches(
            serverURL: serverURL,
            token: token,
            machineID: machineID
        )
        return result
    }

    public func fetchMachines(serverURL: URL, token: String) async throws -> [APIMachine] {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = MachinesCacheKey(
            serverURLString: serverURL.absoluteString,
            token: normalizedToken
        )

        if let cached = machinesCache[cacheKey],
           Date().timeIntervalSince1970 - cached.cachedAt < MachinesCachePolicy.ttl {
            return cached.machines
        }

        if let inFlightTask = inFlightMachineFetches[cacheKey] {
            return try await inFlightTask.value
        }

        let httpClient = self.httpClient
        let request = try MachinesAPI.makeListRequest(serverURL: serverURL, token: normalizedToken)
        let task = Task<[APIMachine], Error> {
            let (data, http) = try await httpClient.data(for: request)
            guard (200..<300).contains(http.statusCode) else {
                throw MachinesAPIError.invalidHTTPStatus(http.statusCode)
            }
            return try MachinesAPI.decodeListResponse(data)
        }

        inFlightMachineFetches[cacheKey] = task
        defer { inFlightMachineFetches[cacheKey] = nil }

        let machines = try await task.value
        machinesCache[cacheKey] = MachinesCacheEntry(
            machines: machines,
            cachedAt: Date().timeIntervalSince1970
        )
        scheduleMachineDataPlanePrewarm(
            machines: machines,
            serverURL: serverURL,
            token: normalizedToken
        )
        return machines
    }

    private func invalidateProjectCaches(
        serverURL: URL,
        token: String,
        machineID: String
    ) {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        projectsCache = projectsCache.filter { key, _ in
            !(key.serverURLString == serverURL.absoluteString &&
                key.token == normalizedToken &&
                key.machineID == normalizedMachineID)
        }
        inFlightProjectFetches = inFlightProjectFetches.filter { key, _ in
            !(key.serverURLString == serverURL.absoluteString &&
                key.token == normalizedToken &&
                key.machineID == normalizedMachineID)
        }
    }

    private func scheduleMachineDataPlanePrewarm(
        machines: [APIMachine],
        serverURL: URL,
        token: String
    ) {
        let prewarmPolicy = self.prewarmPolicy
        Task(priority: .utility) {
            guard await prewarmPolicy.allowsBackgroundPrewarm() else { return }
            await self.performMachineDataPlanePrewarm(
                machines: machines,
                serverURL: serverURL,
                token: token
            )
        }
    }

    private func performMachineDataPlanePrewarm(
        machines: [APIMachine],
        serverURL: URL,
        token: String
    ) async {
        let rpcDirectoryService = self.rpcDirectoryService
        let now = Date().timeIntervalSince1970
        let eligibleMachines = machines.compactMap { machine -> (APIMachine, String)? in
            guard machine.active else { return nil }
            guard machine.activeAt > 0 else { return nil }
            guard now - machine.activeAt <= MachineDataPlanePrewarmConfig.recentActivityInterval else {
                return nil
            }
            guard let wrappedKey = machine.dataEncryptionKey?.trimmingCharacters(in: .whitespacesAndNewlines),
                  wrappedKey.isEmpty == false else {
                return nil
            }

            let prewarmKey = MachineDataPlanePrewarmKey(
                serverURLString: serverURL.absoluteString,
                token: token,
                machineID: machine.id,
                wrappedMachineDataEncryptionKey: wrappedKey
            )
            if let lastPrewarmAt = lastMachineDataPlanePrewarmAt[prewarmKey],
               now - lastPrewarmAt < MachineDataPlanePrewarmConfig.throttleInterval {
                return nil
            }
            lastMachineDataPlanePrewarmAt[prewarmKey] = now
            return (machine, wrappedKey)
        }
        guard !eligibleMachines.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for (machine, wrappedKey) in eligibleMachines {
                group.addTask {
                    await rpcDirectoryService.prewarmMachineDataPlane(
                        serverURL: serverURL,
                        token: token,
                        machineID: machine.id,
                        wrappedMachineDataEncryptionKey: wrappedKey
                    )
                }
            }
        }
    }

    public func deleteMachine(serverURL: URL, token: String, machineID: String) async throws -> APIMachineCommandResult {
        let request = try MachinesAPI.makeDeleteRequest(
            serverURL: serverURL,
            token: token,
            machineID: machineID
        )
        let (data, http) = try await httpClient.data(for: request)
        guard (200..<300).contains(http.statusCode) else {
            let errorMessage = parseServerErrorMessage(from: data)
            if let errorMessage {
                throw MachinesAPIError.rpcCallFailed(errorMessage)
            }
            throw MachinesAPIError.invalidHTTPStatus(http.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(APIMachineCommandResult.self, from: data)
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
            let data = try await rpcDirectoryService.invokeCommand(
                serverURL: serverURL,
                token: token,
                machineID: normalizedMachineID,
                command: "list-models",
                params: ["agent": .string(agent.rawValue)]
            )
            return try MachinesAPI.decodeAgentCapabilitiesResponse(data)
        } catch let error as MachinesAPIError {
            if shouldFallbackToLegacyModelsEndpoint(error) == false {
                throw error
            }
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

    public func setDaemonPreventSleep(
        serverURL: URL,
        token: String,
        machineID: String,
        enabled: Bool
    ) async throws -> APIMachineCommandResult {
        let data = try await rpcDirectoryService.invokeCommand(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            command: "prevent-daemon-sleep",
            params: ["enabled": .bool(enabled)]
        )
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MachinesAPIError.invalidRPCPayload
        }

        let success = payload["success"] as? Bool ?? false
        let normalizedError = (payload["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if !success {
            throw MachinesAPIError.rpcCallFailed(
                (normalizedError?.isEmpty == false ? normalizedError : nil)
                    ?? "Failed to update daemon idle sleep prevention"
            )
        }
        let normalizedMessage = (payload["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return APIMachineCommandResult(
            success: true,
            message: (normalizedMessage?.isEmpty == false ? normalizedMessage : nil)
                ?? (enabled ? "Daemon idle sleep prevention enabled" : "Daemon idle sleep prevention disabled"),
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
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        try await rpcDirectoryService.fetchCodexThreadMessages(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            threadID: threadID,
            transcriptPath: transcriptPath,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            limit: limit,
            cursor: cursor
        )
    }

    public func archiveCodexThread(
        serverURL: URL,
        token: String,
        machineID: String,
        threadID: String,
        transcriptPath: String?,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> APIMachineCommandResult {
        try await rpcDirectoryService.archiveCodexThread(
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
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        try await rpcDirectoryService.fetchClaudeSessionMessages(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            sessionID: sessionID,
            cwd: cwd,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            limit: limit,
            cursor: cursor
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
        wrappedMachineDataEncryptionKey: String?,
        limit: Int,
        cursor: String?
    ) async throws -> APISessionMessagesPage {
        try await rpcDirectoryService.fetchGeminiSessionMessages(
            serverURL: serverURL,
            token: token,
            machineID: machineID,
            sessionID: sessionID,
            wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
            limit: limit,
            cursor: cursor
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

    private func shouldFallbackToLegacyModelsEndpoint(_ error: MachinesAPIError) -> Bool {
        switch error {
        case .rpcTimedOut,
             .rpcSocketConnectionFailed,
             .invalidRPCPayload:
            return true
        case .rpcCallFailed:
            return true
        case .missingToken,
             .missingMachineID,
             .missingThreadID,
             .missingDirectory,
             .missingPath,
             .missingCommand,
             .machineNotFound,
             .endpointUnavailable,
             .invalidHTTPStatus:
            return false
        }
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
