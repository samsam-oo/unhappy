import Foundation
import SocketIO

public protocol MachineRPCDirectoryListing: Sendable {
    func invokeCommand(
        serverURL: URL,
        token: String,
        machineID: String,
        command: String,
        params: [String: Any]
    ) async throws -> Data

    func listDirectory(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        machineDataEncryptionKey: String?
    ) async throws -> APIMachineListDirectoryResult

    func fetchCodexThreadsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APICodexThreadsPage

    func fetchClaudeSessionsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APIClaudeSessionsPage
}

public actor SocketIOMachineRPCDirectoryService: MachineRPCDirectoryListing {
    private let connectTimeoutSeconds: Double
    private let ackTimeoutSeconds: Double

    public init(
        connectTimeoutSeconds: Double = 8,
        ackTimeoutSeconds: Double = 30
    ) {
        self.connectTimeoutSeconds = connectTimeoutSeconds
        self.ackTimeoutSeconds = ackTimeoutSeconds
    }

    public func listDirectory(
        serverURL: URL,
        token: String,
        machineID: String,
        path: String,
        machineDataEncryptionKey _: String?
    ) async throws -> APIMachineListDirectoryResult {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }

        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw MachinesAPIError.missingPath
        }

        let responseData = try await invokeCommand(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            command: "listDirectory",
            params: [
                "path": normalizedPath,
                "includeStats": false,
                "types": ["directory"],
                "sort": true,
                "maxEntries": 2_000,
            ]
        )
        let decoded = try MachinesAPI.decodeListDirectoryResponse(responseData)
        if decoded.success {
            return decoded
        }

        let normalizedError = decoded.error?.trimmingCharacters(in: .whitespacesAndNewlines)
        throw MachinesAPIError.rpcCallFailed(
            (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "RPC call failed"
        )
    }

    public func fetchCodexThreadsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APICodexThreadsPage {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }

        let boundedLimit = min(max(limit, 1), 100)
        var params: [String: Any] = [
            "limit": boundedLimit,
        ]
        let normalizedCWD = cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCWD, !normalizedCWD.isEmpty {
            params["cwd"] = normalizedCWD
        }
        let normalizedCursor = cursor?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCursor, !normalizedCursor.isEmpty {
            params["cursor"] = normalizedCursor
        }

        let responseData = try await invokeCommand(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            command: "codex-list-threads",
            params: params
        )
        let raw = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        if raw?["success"] as? Bool == false {
            let normalizedError = (raw?["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MachinesAPIError.rpcCallFailed(
                (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "RPC call failed"
            )
        }
        return try MachinesAPI.decodeCodexThreadsPageResponse(responseData)
    }

    public func fetchClaudeSessionsPage(
        serverURL: URL,
        token: String,
        machineID: String,
        limit: Int,
        cwd: String?,
        cursor: String?
    ) async throws -> APIClaudeSessionsPage {
        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }

        let boundedLimit = min(max(limit, 1), 100)
        var params: [String: Any] = [
            "limit": boundedLimit,
        ]
        let normalizedCWD = cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCWD, !normalizedCWD.isEmpty {
            params["cwd"] = normalizedCWD
        }
        let normalizedCursor = cursor?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCursor, !normalizedCursor.isEmpty {
            params["cursor"] = normalizedCursor
        }

        let responseData = try await invokeCommand(
            serverURL: serverURL,
            token: token,
            machineID: normalizedMachineID,
            command: "claude-list-sessions",
            params: params
        )
        let raw = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        if raw?["success"] as? Bool == false {
            let normalizedError = (raw?["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MachinesAPIError.rpcCallFailed(
                (normalizedError?.isEmpty == false ? normalizedError : nil) ?? "RPC call failed"
            )
        }
        return try MachinesAPI.decodeClaudeSessionsPageResponse(responseData)
    }

    public func invokeCommand(
        serverURL: URL,
        token: String,
        machineID: String,
        command: String,
        params: [String: Any]
    ) async throws -> Data {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw MachinesAPIError.missingToken
        }

        let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw MachinesAPIError.missingMachineID
        }

        let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCommand.isEmpty else {
            throw MachinesAPIError.missingCommand
        }

        let requestPayload: [String: Any] = [
            "machineId": normalizedMachineID,
            "command": normalizedCommand,
            "params": params,
        ]

        let queue = DispatchQueue(label: "im.unhappy.native.machine-rpc.\(UUID().uuidString)")
        let manager = SocketManager(
            socketURL: serverURL,
            config: [
                .path("/v1/updates"),
                .version(.three),
                .forceWebsockets(true),
                .forceNew(true),
                .reconnects(false),
                .log(false),
                .compress,
                .handleQueue(queue),
            ]
        )
        let socket = manager.defaultSocket

        try await connectSocket(socket, token: normalizedToken)
        defer {
            socket.disconnect()
            manager.disconnect()
        }

        let ackItems = try await emitWithAck(
            socket: socket,
            event: "machine-public-command",
            payload: requestPayload
        )

        if let first = ackItems.first as? String, first == SocketAckStatus.noAck.rawValue {
            throw MachinesAPIError.rpcTimedOut
        }

        guard let responseObject = ackItems.first as? [String: Any] else {
            throw MachinesAPIError.invalidRPCPayload
        }
        guard JSONSerialization.isValidJSONObject(responseObject) else {
            throw MachinesAPIError.invalidRPCPayload
        }

        return try JSONSerialization.data(withJSONObject: responseObject)
    }

    private func connectSocket(_ socket: SocketIOClient, token: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var completed = false
            var handlerIDs: [UUID] = []

            func finish(_ result: Result<Void, Error>) {
                guard !completed else { return }
                completed = true
                for handlerID in handlerIDs {
                    socket.off(id: handlerID)
                }
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            handlerIDs.append(
                socket.on(clientEvent: .connect) { _, _ in
                    finish(.success(()))
                }
            )

            handlerIDs.append(
                socket.on(clientEvent: .error) { data, _ in
                    let reason = data.first.map(String.init(describing:)) ?? "Socket connection error"
                    finish(.failure(MachinesAPIError.rpcSocketConnectionFailed(reason)))
                }
            )

            handlerIDs.append(
                socket.on(clientEvent: .disconnect) { data, _ in
                    guard !completed else { return }
                    let reason = data.first.map(String.init(describing:)) ?? "Socket disconnected"
                    finish(.failure(MachinesAPIError.rpcSocketConnectionFailed(reason)))
                }
            )

            socket.connect(
                withPayload: [
                    "token": token,
                    "clientType": "user-scoped",
                ],
                timeoutAfter: connectTimeoutSeconds
            ) {
                finish(.failure(MachinesAPIError.rpcSocketConnectionFailed("Connection timeout")))
            }
        }
    }

    private func emitWithAck(
        socket: SocketIOClient,
        event: String,
        payload: [String: Any]
    ) async throws -> [Any] {
        try await withCheckedThrowingContinuation { continuation in
            socket.rawEmitView
                .emitWithAck(event, with: [payload])
                .timingOut(after: ackTimeoutSeconds) { items in
                    continuation.resume(returning: items)
                }
        }
    }
}
