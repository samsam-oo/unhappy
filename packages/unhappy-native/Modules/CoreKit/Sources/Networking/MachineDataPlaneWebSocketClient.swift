import Foundation
import SecurityKit

public actor MachineDataPlaneWebSocketClient {
    private enum RequestPriority: Int, Comparable, Sendable {
        case background = 0
        case normal = 1
        case interactive = 2

        static func < (lhs: RequestPriority, rhs: RequestPriority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        static func forOperation(_ operation: MachineDataPlaneOperation) -> RequestPriority {
            switch operation {
            case .codexSendMessage,
                 .claudeSendMessage,
                 .geminiSendMessage,
                 .fsReadFile,
                 .execBash,
                 .providerSpawn:
                return .interactive

            case .codexListMessages,
                 .claudeListMessages,
                 .geminiListMessages,
                 .codexListThreads,
                 .claudeListSessions,
                 .geminiListSessions:
                return .background

            default:
                return .normal
            }
        }
    }

    private struct ConnectionKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let machineID: String
        let machineDataKeyBase64URL: String
    }

    private struct QueuedRequest {
        let operation: MachineDataPlaneOperation
        let bodyObject: Any
        let priority: RequestPriority
        let continuation: CheckedContinuation<Data, Error>
    }

    private struct LiveConnection {
        let task: URLSessionWebSocketTask
        let sessionKey: Data
        var lastActivityAt: TimeInterval
    }

    private struct ConnectionState {
        let machineDataKey: Data
        var liveConnection: LiveConnection?
        var queuedRequests: [QueuedRequest] = []
        var isProcessing = false
    }

    private struct RetryableRequestError: Error {
        let message: String
    }

    private let session: URLSession
    private let requestTimeoutInterval: TimeInterval
    private let staleConnectionProbeInterval: TimeInterval
    private let retryableErrorRetryDelay: Duration
    private var connectionStates: [ConnectionKey: ConnectionState] = [:]
    private var inFlightConnections: [ConnectionKey: Task<LiveConnection, Error>] = [:]

    public init(
        session: URLSession = .shared,
        requestTimeoutInterval: TimeInterval = 8,
        staleConnectionProbeInterval: TimeInterval = 5,
        retryableErrorRetryDelay: Duration = .milliseconds(350)
    ) {
        self.session = session
        self.requestTimeoutInterval = requestTimeoutInterval
        self.staleConnectionProbeInterval = staleConnectionProbeInterval
        self.retryableErrorRetryDelay = retryableErrorRetryDelay
    }

    public func requestJSON(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        operation: MachineDataPlaneOperation,
        bodyObject: Any
    ) async throws -> Data {
        guard let machineDataKey = MachineDataPlaneEncryption.resolveMachineDataKey(
            rawWrappedKey: wrappedMachineDataEncryptionKey
        ) else {
            throw MachinesAPIError.rpcCallFailed("Machine data encryption key is unavailable")
        }

        let key = ConnectionKey(
            serverURLString: serverURL.absoluteString,
            token: token,
            machineID: machineID,
            machineDataKeyBase64URL: Base64URLCodec.encode(machineDataKey)
        )

        return try await withCheckedThrowingContinuation { continuation in
            enqueueRequest(
                QueuedRequest(
                    operation: operation,
                    bodyObject: bodyObject,
                    priority: RequestPriority.forOperation(operation),
                    continuation: continuation
                ),
                machineDataKey: machineDataKey,
                for: key,
                serverURL: serverURL
            )
        }
    }

    public func prewarmConnection(
        serverURL: URL,
        token: String,
        machineID: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws {
        guard let machineDataKey = MachineDataPlaneEncryption.resolveMachineDataKey(
            rawWrappedKey: wrappedMachineDataEncryptionKey
        ) else {
            throw MachinesAPIError.rpcCallFailed("Machine data encryption key is unavailable")
        }

        let key = ConnectionKey(
            serverURLString: serverURL.absoluteString,
            token: token,
            machineID: machineID,
            machineDataKeyBase64URL: Base64URLCodec.encode(machineDataKey)
        )

        if connectionStates[key] == nil {
            connectionStates[key] = ConnectionState(machineDataKey: machineDataKey)
        }

        _ = try await liveConnection(for: key, serverURL: serverURL)
    }

    nonisolated func mapTransportError(_ error: Error) -> MachinesAPIError {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == 57 {
            return .rpcCallFailed("Machine data-plane socket is not connected")
        }
        if nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorNetworkConnectionLost ||
            nsError.code == NSURLErrorCannotConnectToHost ||
            nsError.code == NSURLErrorTimedOut {
            return .rpcTimedOut
        }
        return .rpcCallFailed(nsError.localizedDescription)
    }

    private func makeTask(serverURL: URL, token: String, machineID: String) throws -> URLSessionWebSocketTask {
        guard let url = dataPlaneURL(serverURL: serverURL, machineID: machineID) else {
            throw MachinesAPIError.invalidRPCPayload
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(MachineDataPlaneProtocol.subprotocol, forHTTPHeaderField: "Sec-WebSocket-Protocol")
        request.timeoutInterval = requestTimeoutInterval
        return session.webSocketTask(with: request)
    }

    private func dataPlaneURL(serverURL: URL, machineID: String) -> URL? {
        guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/v1/machines/\(machineID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? machineID)/data-plane"
        components.query = nil
        return components.url
    }

    private func receiveHelloAck(task: URLSessionWebSocketTask) async throws -> MachineDataPlaneHelloAckFrame {
        let message = try await task.receive()
        guard case .string(let text) = message else {
            throw MachinesAPIError.invalidRPCPayload
        }
        return try JSONDecoder().decode(MachineDataPlaneHelloAckFrame.self, from: Data(text.utf8))
    }

    private func sendPing(task: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func enqueueRequest(
        _ request: QueuedRequest,
        machineDataKey: Data,
        for key: ConnectionKey,
        serverURL: URL
    ) {
        var state = connectionStates[key] ?? ConnectionState(machineDataKey: machineDataKey)
        let insertionIndex = state.queuedRequests.partitioningIndex { queuedRequest in
            queuedRequest.priority < request.priority
        }
        state.queuedRequests.insert(request, at: insertionIndex)
        let shouldStartProcessing = state.isProcessing == false
        state.isProcessing = true
        connectionStates[key] = state

        guard shouldStartProcessing else { return }
        Task { [weak self] in
            await self?.processQueue(for: key, serverURL: serverURL)
        }
    }

    private func processQueue(for key: ConnectionKey, serverURL: URL) async {
        while true {
            guard var state = connectionStates[key] else { return }
            guard state.queuedRequests.isEmpty == false else {
                state.isProcessing = false
                connectionStates[key] = state
                return
            }

            let request = state.queuedRequests.removeFirst()
            connectionStates[key] = state

            do {
                let response = try await performRequest(
                    request,
                    for: key,
                    serverURL: serverURL,
                    allowReconnectRetry: true
                )
                request.continuation.resume(returning: response)
            } catch {
                request.continuation.resume(throwing: error)
            }
        }
    }

    private func performRequest(
        _ request: QueuedRequest,
        for key: ConnectionKey,
        serverURL: URL,
        allowReconnectRetry: Bool
    ) async throws -> Data {
        do {
            let liveConnection = try await liveConnection(for: key, serverURL: serverURL)
            return try await performRequest(
                request,
                using: liveConnection
            )
        } catch {
            let mappedError = (error as? MachinesAPIError) ?? mapTransportError(error)
            if allowReconnectRetry, shouldRetryAfterConnectionFailure(mappedError) {
                invalidateConnection(for: key)
                if case .rpcCallFailed(let message) = mappedError,
                   message == "Peer data-plane connection is not ready" {
                    try? await Task.sleep(for: .milliseconds(250))
                }
                return try await performRequest(
                    request,
                    for: key,
                    serverURL: serverURL,
                    allowReconnectRetry: false
                )
            }
            invalidateConnection(for: key)
            throw mappedError
        }
    }

    private func liveConnection(
        for key: ConnectionKey,
        serverURL: URL
    ) async throws -> LiveConnection {
        if let existingConnection = connectionStates[key]?.liveConnection {
            let now = Date().timeIntervalSince1970
            if now - existingConnection.lastActivityAt >= staleConnectionProbeInterval {
                do {
                    try await sendPing(task: existingConnection.task)
                } catch {
                    invalidateConnection(for: key)
                }
            } else {
                var refreshed = existingConnection
                refreshed.lastActivityAt = now
                connectionStates[key]?.liveConnection = refreshed
                return refreshed
            }

            if let refreshedConnection = connectionStates[key]?.liveConnection {
                var refreshed = refreshedConnection
                refreshed.lastActivityAt = now
                connectionStates[key]?.liveConnection = refreshed
                return refreshed
            }
        }

        if let inFlightConnection = inFlightConnections[key] {
            return try await inFlightConnection.value
        }

        guard let machineDataKey = connectionStates[key]?.machineDataKey else {
            throw MachinesAPIError.rpcCallFailed("Machine data encryption key is unavailable")
        }

        let connectTask = Task<LiveConnection, Error> {
            let task = try makeTask(
                serverURL: serverURL,
                token: key.token,
                machineID: key.machineID
            )
            task.resume()

            do {
                let handshake = try MachineDataPlaneEncryption.generateSessionHandshakeMaterial()
                let hello = MachineDataPlaneHelloFrame(
                    connectionID: UUID().uuidString,
                    role: .native,
                    keyExchange: MachineDataPlaneKeyExchange(
                        publicKey: handshake.publicKeyBase64URL,
                        nonce: handshake.nonceBase64URL
                    )
                )
                try await send(frame: hello, task: task)

                let helloAck = try await receiveHelloAck(task: task)
                let sessionKey = try MachineDataPlaneEncryption.deriveSessionKey(
                    machineDataKey: machineDataKey,
                    localPrivateKey: handshake.privateKey,
                    localNonceBase64URL: handshake.nonceBase64URL,
                    peerPublicKeyBase64URL: helloAck.keyExchange.publicKey,
                    peerNonceBase64URL: helloAck.keyExchange.nonce,
                    role: "native"
                )

                return LiveConnection(
                    task: task,
                    sessionKey: sessionKey,
                    lastActivityAt: Date().timeIntervalSince1970
                )
            } catch {
                task.cancel(with: .goingAway, reason: nil)
                throw error
            }
        }

        inFlightConnections[key] = connectTask
        defer { inFlightConnections[key] = nil }

        let liveConnection = try await connectTask.value
        var updatedConnection = liveConnection
        updatedConnection.lastActivityAt = Date().timeIntervalSince1970
        connectionStates[key]?.liveConnection = updatedConnection
        return updatedConnection
    }

    private func performRequest(
        _ request: QueuedRequest,
        using liveConnection: LiveConnection
    ) async throws -> Data {
        let streamID = UUID().uuidString
        let requestHeader = MachineDataPlaneRequestFrame(
            streamID: streamID,
            op: request.operation,
            body: MachineDataPlaneSealedBody(nonce: "", ciphertext: "", tag: ""),
            expectsChunks: false
        )
        let sealedBody = try MachineDataPlaneEncryption.encryptDataPlaneJSONObject(
            request.bodyObject,
            sessionKey: liveConnection.sessionKey,
            authenticatedData: requestAAD(for: requestHeader)
        )
        let requestFrame = MachineDataPlaneRequestFrame(
            streamID: streamID,
            op: request.operation,
            body: MachineDataPlaneSealedBody(
                nonce: sealedBody.nonce,
                ciphertext: sealedBody.ciphertext,
                tag: sealedBody.tag
            ),
            expectsChunks: false
        )
        try await send(frame: requestFrame, task: liveConnection.task)

        while true {
            let message = try await liveConnection.task.receive()
            guard case .string(let text) = message else { continue }

            if let errorFrame = try? JSONDecoder().decode(
                MachineDataPlaneErrorFrame.self,
                from: Data(text.utf8)
            ), errorFrame.streamID == streamID {
                throw MachinesAPIError.rpcCallFailed(errorFrame.message)
            }

            if let completeFrame = try? JSONDecoder().decode(
                MachineDataPlaneCompleteFrame.self,
                from: Data(text.utf8)
            ), completeFrame.streamID == streamID {
                return try MachineDataPlaneEncryption.decryptDataPlanePayload(
                    MachineDataPlaneSealedPayload(
                        nonce: completeFrame.body.nonce,
                        ciphertext: completeFrame.body.ciphertext,
                        tag: completeFrame.body.tag
                    ),
                    sessionKey: liveConnection.sessionKey,
                    authenticatedData: completeAAD(for: completeFrame)
                )
            }
        }
    }

    private func invalidateConnection(for key: ConnectionKey) {
        guard var state = connectionStates[key] else { return }
        state.liveConnection?.task.cancel(with: .goingAway, reason: nil)
        state.liveConnection = nil
        connectionStates[key] = state
        inFlightConnections[key]?.cancel()
        inFlightConnections[key] = nil
    }

    private func shouldRetryAfterConnectionFailure(_ error: MachinesAPIError) -> Bool {
        switch error {
        case .rpcTimedOut:
            return true
        case .rpcCallFailed(let message):
            return message == "Machine data-plane socket is not connected" ||
                message == "Peer data-plane connection is not ready"
        default:
            return false
        }
    }

    private func send<T: Encodable>(frame: T, task: URLSessionWebSocketTask) async throws {
        let data = try JSONEncoder().encode(frame)
        guard let text = String(data: data, encoding: .utf8) else {
            throw MachinesAPIError.invalidRPCPayload
        }
        try await task.send(.string(text))
    }

    private func requestAAD(for frame: MachineDataPlaneRequestFrame) -> Data {
        aadData([
            ("v", String(frame.v)),
            ("t", frame.t.rawValue),
            ("streamId", frame.streamID),
            ("op", frame.op.rawValue),
            ("expectsChunks", frame.expectsChunks ? "1" : "0"),
        ])
    }

    private func completeAAD(for frame: MachineDataPlaneCompleteFrame) -> Data {
        aadData([
            ("v", String(frame.v)),
            ("t", frame.t.rawValue),
            ("streamId", frame.streamID),
            ("seq", String(frame.seq)),
            ("hasMore", frame.hasMore == true ? "1" : "0"),
            ("nextCursor", frame.nextCursor ?? ""),
        ])
    }

    private func aadData(_ entries: [(String, String)]) -> Data {
        Data(entries.map { "\($0.0)=\($0.1)" }.joined(separator: "\n").utf8)
    }
}

private extension Array {
    func partitioningIndex(
        where predicate: (Element) -> Bool
    ) -> Int {
        var low = startIndex
        var high = endIndex

        while low < high {
            let distance = self.distance(from: low, to: high)
            let mid = index(low, offsetBy: distance / 2)
            if predicate(self[mid]) {
                low = index(after: mid)
            } else {
                high = mid
            }
        }

        return low
    }
}
