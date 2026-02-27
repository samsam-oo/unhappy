import Foundation
import SocketIO

public protocol SessionRPCCommandDispatching: Sendable {
    func invokeCommand(
        serverURL: URL,
        token: String,
        sessionID: String,
        command: String,
        params: [String: Any],
        allowMachineFallback: Bool
    ) async throws -> Data
}

public actor SocketIOSessionRPCCommandService: SessionRPCCommandDispatching {
    private let connectTimeoutSeconds: Double
    private let ackTimeoutSeconds: Double
    private var liveConnection: LiveConnection?

    private struct LiveConnection {
        let serverURLString: String
        let token: String
        let manager: SocketManager
        let socket: SocketIOClient
    }

    public init(
        connectTimeoutSeconds: Double = 8,
        ackTimeoutSeconds: Double = 30
    ) {
        self.connectTimeoutSeconds = connectTimeoutSeconds
        self.ackTimeoutSeconds = ackTimeoutSeconds
    }

    public func invokeCommand(
        serverURL: URL,
        token: String,
        sessionID: String,
        command: String,
        params: [String: Any],
        allowMachineFallback: Bool
    ) async throws -> Data {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw SessionsAPIError.missingToken
        }

        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else {
            throw SessionsAPIError.missingSessionID
        }

        let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCommand.isEmpty else {
            throw SessionsAPIError.missingCommand
        }

        let requestPayload: [String: Any] = [
            "sessionId": normalizedSessionID,
            "command": normalizedCommand,
            "params": params,
            "allowMachineFallback": allowMachineFallback,
        ]

        let socket = try await getOrCreateConnectedSocket(
            serverURL: serverURL,
            token: normalizedToken
        )

        do {
            let ackItems = try await emitWithAck(
                socket: socket,
                event: "session-public-command",
                payload: requestPayload
            )

            if let first = ackItems.first as? String, first == SocketAckStatus.noAck.rawValue {
                teardownLiveConnection()
                throw SessionsAPIError.rpcTimedOut
            }

            guard let responseObject = ackItems.first as? [String: Any] else {
                teardownLiveConnection()
                throw SessionsAPIError.invalidRPCPayload
            }
            guard JSONSerialization.isValidJSONObject(responseObject) else {
                teardownLiveConnection()
                throw SessionsAPIError.invalidRPCPayload
            }

            guard let ok = responseObject["ok"] as? Bool else {
                teardownLiveConnection()
                throw SessionsAPIError.invalidRPCPayload
            }
            if !ok {
                teardownLiveConnection()
                let rawError = responseObject["error"] as? String
                let message = rawError?.trimmingCharacters(in: .whitespacesAndNewlines)
                throw SessionsAPIError.rpcCallFailed(
                    (message?.isEmpty == false ? message : nil) ?? "Session RPC command failed"
                )
            }

            guard let bodyObject = responseObject["body"] else {
                teardownLiveConnection()
                throw SessionsAPIError.invalidRPCPayload
            }
            guard JSONSerialization.isValidJSONObject(bodyObject) else {
                teardownLiveConnection()
                throw SessionsAPIError.invalidRPCPayload
            }

            return try JSONSerialization.data(withJSONObject: bodyObject)
        } catch {
            teardownLiveConnection()
            throw error
        }
    }

    private func getOrCreateConnectedSocket(
        serverURL: URL,
        token: String
    ) async throws -> SocketIOClient {
        let serverURLString = serverURL.absoluteString

        if let liveConnection {
            let sameIdentity =
                liveConnection.serverURLString == serverURLString &&
                liveConnection.token == token
            if sameIdentity, liveConnection.socket.status == .connected {
                return liveConnection.socket
            }
            teardownLiveConnection()
        }

        let queue = DispatchQueue(label: "im.unhappy.native.session-rpc.\(UUID().uuidString)")
        let manager = SocketManager(
            socketURL: serverURL,
            config: [
                .path("/v1/updates"),
                .version(.three),
                .reconnects(false),
                .log(false),
                .compress,
                .handleQueue(queue),
            ]
        )
        let socket = manager.defaultSocket
        do {
            try await connectSocket(socket, token: token)
        } catch {
            socket.disconnect()
            manager.disconnect()
            throw error
        }

        liveConnection = LiveConnection(
            serverURLString: serverURLString,
            token: token,
            manager: manager,
            socket: socket
        )
        return socket
    }

    private func teardownLiveConnection() {
        guard let liveConnection else { return }
        liveConnection.socket.disconnect()
        liveConnection.manager.disconnect()
        self.liveConnection = nil
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
                    finish(.failure(SessionsAPIError.rpcSocketConnectionFailed(reason)))
                }
            )

            handlerIDs.append(
                socket.on(clientEvent: .disconnect) { data, _ in
                    guard !completed else { return }
                    let reason = data.first.map(String.init(describing:)) ?? "Socket disconnected"
                    finish(.failure(SessionsAPIError.rpcSocketConnectionFailed(reason)))
                }
            )

            socket.connect(
                withPayload: [
                    "token": token,
                    "clientType": "user-scoped",
                ],
                timeoutAfter: connectTimeoutSeconds
            ) {
                finish(.failure(SessionsAPIError.rpcSocketConnectionFailed("Connection timeout")))
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
