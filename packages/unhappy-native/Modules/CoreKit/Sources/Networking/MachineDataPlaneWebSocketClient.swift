import Foundation
import Network
import SecurityKit

public actor MachineDataPlaneWebSocketClient {
    private enum ConnectionPhase: Sendable {
        case idle
        case connecting
        case connected
        case reconnecting
    }

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

            case .machinePing,
                 .codexListMessages,
                 .claudeListMessages,
                 .geminiListMessages,
                 .projectSessions,
                 .codexListThreads,
                 .claudeListSessions,
                 .geminiListSessions,
                 .machineListModels,
                 .projectList:
                return .normal

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
        let id: String
        let operation: MachineDataPlaneOperation
        let bodyObject: Any
        let priority: RequestPriority
        let continuation: CheckedContinuation<Data, Error>
    }

    private enum StreamTerminalFrame: Sendable {
        case complete(MachineDataPlaneCompleteFrame)
        case error(MachineDataPlaneErrorFrame)
    }

    private struct ActiveStream {
        let requestID: String
        let continuation: CheckedContinuation<StreamTerminalFrame, Error>
        let timeoutTask: Task<Void, Never>
    }

    private struct LiveConnection {
        let transport: any MachineDataPlaneTextTransport
        let sessionKey: Data
        let maxInFlightStreams: Int
    }

    private struct ConnectionState {
        let machineDataKey: Data
        var liveConnection: LiveConnection?
        var queuedRequests: [QueuedRequest] = []
        var dispatchedRequests: [String: QueuedRequest] = [:]
        var isPumpScheduled = false
        var lastConnectionFailureAt: TimeInterval?
        var phase: ConnectionPhase = .idle
        var activeExecutionCount = 0
        var activeStreams: [String: ActiveStream] = [:]
        var bufferedTerminalFrames: [String: StreamTerminalFrame] = [:]
        var readerTask: Task<Void, Never>?
        var needsIdleProbe = false
        var idleProbeTask: Task<Void, Error>?
    }

    private let requestTimeoutInterval: TimeInterval
    private let responseTimeoutInterval: TimeInterval
    private let backgroundReconnectBackoffInterval: TimeInterval
    private let reconnectGraceInterval: TimeInterval
    private let idleProbeTimeoutInterval: TimeInterval
    private var connectionStates: [ConnectionKey: ConnectionState] = [:]
    private var inFlightConnections: [ConnectionKey: Task<LiveConnection, Error>] = [:]

    public init(
        requestTimeoutInterval: TimeInterval = 8,
        responseTimeoutInterval: TimeInterval = 30,
        backgroundReconnectBackoffInterval: TimeInterval = 10,
        reconnectGraceInterval: TimeInterval = 4
    ) {
        self.requestTimeoutInterval = requestTimeoutInterval
        self.responseTimeoutInterval = responseTimeoutInterval
        self.backgroundReconnectBackoffInterval = backgroundReconnectBackoffInterval
        self.reconnectGraceInterval = reconnectGraceInterval
        self.idleProbeTimeoutInterval = max(min(requestTimeoutInterval, 3), 1)
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
        let requestID = UUID().uuidString

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                enqueueRequest(
                    QueuedRequest(
                        id: requestID,
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
        } onCancel: {
            Task { [weak self] in
                await self?.cancelQueuedRequest(id: requestID, for: key)
            }
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
        if let machinesError = error as? MachinesAPIError {
            return machinesError
        }
        if let nwError = error as? NWError {
            switch nwError {
            case .posix(.ENOTCONN), .posix(.ECONNABORTED), .posix(.ECONNRESET):
                return .rpcCallFailed("Machine data-plane socket is not connected")
            case .posix(.ETIMEDOUT):
                return .rpcTimedOut
            default:
                return .rpcCallFailed(nwError.debugDescription)
            }
        }
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

    private func makeTransport(
        serverURL: URL,
        token: String,
        machineID: String
    ) throws -> any MachineDataPlaneTextTransport {
        guard let url = dataPlaneURL(serverURL: serverURL, machineID: machineID) else {
            throw MachinesAPIError.invalidRPCPayload
        }
        return MachineDataPlaneNetworkTransport(
            url: url,
            token: token,
            subprotocol: MachineDataPlaneProtocol.subprotocol,
            connectTimeoutInterval: requestTimeoutInterval
        )
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

    private func receiveHelloAck(
        transport: any MachineDataPlaneTextTransport
    ) async throws -> MachineDataPlaneHelloAckFrame {
        let text = try await transport.receiveText()
        return try JSONDecoder().decode(MachineDataPlaneHelloAckFrame.self, from: Data(text.utf8))
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
        connectionStates[key] = state
        schedulePump(for: key, serverURL: serverURL)
    }

    private func schedulePump(for key: ConnectionKey, serverURL: URL) {
        guard var state = connectionStates[key] else { return }
        guard !state.isPumpScheduled else { return }
        state.isPumpScheduled = true
        connectionStates[key] = state
        Task { [weak self] in
            await self?.pumpQueue(for: key, serverURL: serverURL)
        }
    }

    private func pumpQueue(for key: ConnectionKey, serverURL: URL) async {
        while true {
            guard var state = connectionStates[key] else { return }
            let capacity = Self.dispatchCapacity(
                maxInFlightStreams: state.liveConnection?.maxInFlightStreams,
                activeExecutions: state.activeExecutionCount
            )
            guard state.queuedRequests.isEmpty == false, capacity > 0 else {
                state.isPumpScheduled = false
                connectionStates[key] = state
                return
            }

            let request = state.queuedRequests.removeFirst()
            state.activeExecutionCount += 1
            state.dispatchedRequests[request.id] = request
            connectionStates[key] = state
            let requestID = request.id
            Task { [weak self, requestID, key, serverURL] in
                await self?.runQueuedRequest(id: requestID, for: key, serverURL: serverURL)
            }
        }
    }

    private func cancelQueuedRequest(id: String, for key: ConnectionKey) {
        guard var state = connectionStates[key] else { return }
        guard let index = state.queuedRequests.firstIndex(where: { $0.id == id }) else { return }
        let request = state.queuedRequests.remove(at: index)
        connectionStates[key] = state
        request.continuation.resume(throwing: CancellationError())
    }

    private func runQueuedRequest(
        id requestID: String,
        for key: ConnectionKey,
        serverURL: URL
    ) async {
        guard let request = dispatchedRequest(id: requestID, for: key) else {
            requestDidFinish(requestID: requestID, for: key, serverURL: serverURL)
            return
        }
        defer {
            requestDidFinish(requestID: requestID, for: key, serverURL: serverURL)
        }

        do {
            let response = try await performRequest(
                request,
                for: key,
                serverURL: serverURL,
                allowReconnectRetry: request.priority != .background
            )
            request.continuation.resume(returning: response)
        } catch {
            request.continuation.resume(throwing: error)
        }
    }

    private func dispatchedRequest(id: String, for key: ConnectionKey) -> QueuedRequest? {
        connectionStates[key]?.dispatchedRequests[id]
    }

    private func requestDidFinish(requestID: String, for key: ConnectionKey, serverURL: URL) {
        guard var state = connectionStates[key] else { return }
        state.activeExecutionCount = max(state.activeExecutionCount - 1, 0)
        state.dispatchedRequests.removeValue(forKey: requestID)
        if state.activeExecutionCount == 0, state.liveConnection != nil {
            state.needsIdleProbe = true
        }
        connectionStates[key] = state
        schedulePump(for: key, serverURL: serverURL)
    }

    private func performRequest(
        _ request: QueuedRequest,
        for key: ConnectionKey,
        serverURL: URL,
        allowReconnectRetry: Bool
    ) async throws -> Data {
        if request.priority == .background,
           shouldThrottleBackgroundReconnect(for: key) {
            throw MachinesAPIError.rpcCallFailed("Machine data-plane socket is not connected")
        }

        let deadline = allowReconnectRetry
            ? Date().timeIntervalSince1970 + reconnectGraceIntervalForPriority(request.priority)
            : nil
        var reconnectAttempt = 0
        var sentRequest = false

        while true {
            do {
                let liveConnection = try await liveConnection(for: key, serverURL: serverURL)
                return try await performRequest(
                    request,
                    using: liveConnection,
                    for: key,
                    sentRequest: &sentRequest,
                    responseTimeoutInterval: Self.responseTimeoutInterval(
                        for: request.operation,
                        baseResponseTimeoutInterval: responseTimeoutInterval
                    )
                )
            } catch {
                let mappedError = (error as? MachinesAPIError) ?? mapTransportError(error)
                if shouldReconnectRequest(
                    request,
                    after: mappedError,
                    sentRequest: sentRequest,
                    deadline: deadline
                ) {
                    reconnectAttempt += 1
                    markConnectionPhase(.reconnecting, for: key)
                    invalidateConnection(for: key)
                    let delay = Self.reconnectBackoffDelay(attempt: reconnectAttempt)
                    if delay > 0 {
                        let nanoseconds = UInt64(max(delay, 0.001) * 1_000_000_000)
                        try? await Task.sleep(nanoseconds: nanoseconds)
                    }
                    sentRequest = false
                    continue
                }

                recordConnectionFailure(for: key)
                invalidateConnection(for: key)
                throw mappedError
            }
        }
    }

    private func liveConnection(
        for key: ConnectionKey,
        serverURL: URL
    ) async throws -> LiveConnection {
        if let existingConnection = connectionStates[key]?.liveConnection {
            clearRecordedConnectionFailure(for: key)
            markConnectionPhase(.connected, for: key)
            try await probeIdleConnectionIfNeeded(for: key, liveConnection: existingConnection)
            guard let liveConnection = connectionStates[key]?.liveConnection else {
                throw MachinesAPIError.rpcCallFailed("Machine data-plane socket is not connected")
            }
            return liveConnection
        }

        if let inFlightConnection = inFlightConnections[key] {
            return try await inFlightConnection.value
        }

        guard let machineDataKey = connectionStates[key]?.machineDataKey else {
            throw MachinesAPIError.rpcCallFailed("Machine data encryption key is unavailable")
        }

        markConnectionPhase(.connecting, for: key)

        let connectTask = Task<LiveConnection, Error> {
            let transport = try makeTransport(
                serverURL: serverURL,
                token: key.token,
                machineID: key.machineID
            )

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
                try await send(frame: hello, transport: transport)

                let helloAck = try await receiveHelloAck(transport: transport)
                await transport.configureKeepalive(idleTimeoutSeconds: helloAck.idleTimeoutSeconds)
                let sessionKey = try MachineDataPlaneEncryption.deriveSessionKey(
                    machineDataKey: machineDataKey,
                    localPrivateKey: handshake.privateKey,
                    localNonceBase64URL: handshake.nonceBase64URL,
                    peerPublicKeyBase64URL: helloAck.keyExchange.publicKey,
                    peerNonceBase64URL: helloAck.keyExchange.nonce,
                    role: "native"
                )

                return LiveConnection(
                    transport: transport,
                    sessionKey: sessionKey,
                    maxInFlightStreams: max(helloAck.maxInFlightStreams, 1)
                )
            } catch {
                await transport.close()
                throw error
            }
        }

        inFlightConnections[key] = connectTask
        defer { inFlightConnections[key] = nil }

        let liveConnection = try await connectTask.value
        if var state = connectionStates[key] {
            state.liveConnection = liveConnection
            state.phase = .connected
            state.lastConnectionFailureAt = nil
            state.needsIdleProbe = false
            state.idleProbeTask = nil
            if state.readerTask == nil {
                state.readerTask = makeReaderTask(for: key, transport: liveConnection.transport)
            }
            connectionStates[key] = state
        }
        schedulePump(for: key, serverURL: serverURL)
        return liveConnection
    }

    private func performRequest(
        _ request: QueuedRequest,
        using liveConnection: LiveConnection,
        for key: ConnectionKey,
        sentRequest: inout Bool,
        responseTimeoutInterval: TimeInterval
    ) async throws -> Data {
        let streamID = UUID().uuidString
        let requestHeader = MachineDataPlaneRequestFrame(
            streamID: streamID,
            op: request.operation,
            body: MachineDataPlaneSealedBody(nonce: "", ciphertext: "", tag: "")
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
            )
        )
        try await withMachineDataPlaneTimeout(
            Self.sendTimeoutInterval(
                for: request.operation,
                baseRequestTimeoutInterval: requestTimeoutInterval
            )
        ) {
            try await self.send(frame: requestFrame, transport: liveConnection.transport)
        }
        sentRequest = true

        let terminalFrame = try await awaitStreamTerminalFrame(
            streamID: streamID,
            requestID: request.id,
            for: key,
            timeoutInterval: responseTimeoutInterval
        )

        switch terminalFrame {
        case .error(let errorFrame):
            throw MachinesAPIError.rpcCallFailed(errorFrame.message)
        case .complete(let completeFrame):
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

    private func probeIdleConnectionIfNeeded(
        for key: ConnectionKey,
        liveConnection: LiveConnection
    ) async throws {
        guard let state = connectionStates[key], state.liveConnection != nil else { return }
        guard state.needsIdleProbe else { return }

        if let idleProbeTask = state.idleProbeTask {
            try await idleProbeTask.value
            return
        }

        let idleProbeTask = Task<Void, Error> { [weak self] in
            guard let self else { return }
            try await self.performIdleProbe(using: liveConnection, for: key)
        }

        if var currentState = connectionStates[key] {
            currentState.idleProbeTask = idleProbeTask
            connectionStates[key] = currentState
        }

        do {
            try await idleProbeTask.value
            if var currentState = connectionStates[key] {
                currentState.idleProbeTask = nil
                currentState.needsIdleProbe = false
                connectionStates[key] = currentState
            }
        } catch {
            if var currentState = connectionStates[key] {
                currentState.idleProbeTask = nil
                currentState.needsIdleProbe = true
                connectionStates[key] = currentState
            }
            let mappedError = (error as? MachinesAPIError) ?? mapTransportError(error)
            recordConnectionFailure(for: key)
            invalidateConnection(for: key)
            throw mappedError
        }
    }

    private func performIdleProbe(
        using liveConnection: LiveConnection,
        for key: ConnectionKey
    ) async throws {
        let streamID = UUID().uuidString
        let requestHeader = MachineDataPlaneRequestFrame(
            streamID: streamID,
            op: .machinePing,
            body: MachineDataPlaneSealedBody(nonce: "", ciphertext: "", tag: "")
        )
        let sealedBody = try MachineDataPlaneEncryption.encryptDataPlaneJSONObject(
            ["reason": "idle-reuse"],
            sessionKey: liveConnection.sessionKey,
            authenticatedData: requestAAD(for: requestHeader)
        )
        let requestFrame = MachineDataPlaneRequestFrame(
            streamID: streamID,
            op: .machinePing,
            body: MachineDataPlaneSealedBody(
                nonce: sealedBody.nonce,
                ciphertext: sealedBody.ciphertext,
                tag: sealedBody.tag
            )
        )

        try await withMachineDataPlaneTimeout(idleProbeTimeoutInterval) {
            try await self.send(frame: requestFrame, transport: liveConnection.transport)
        }

        let terminalFrame = try await awaitStreamTerminalFrame(
            streamID: streamID,
            requestID: "probe:\(streamID)",
            for: key,
            timeoutInterval: idleProbeTimeoutInterval
        )

        switch terminalFrame {
        case .error(let errorFrame):
            throw MachinesAPIError.rpcCallFailed(errorFrame.message)
        case .complete(let completeFrame):
            _ = try MachineDataPlaneEncryption.decryptDataPlanePayload(
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

    private func awaitStreamTerminalFrame(
        streamID: String,
        requestID: String,
        for key: ConnectionKey,
        timeoutInterval: TimeInterval
    ) async throws -> StreamTerminalFrame {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = Task { [weak self] in
                    let nanoseconds = UInt64(max(timeoutInterval, 0.001) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    guard !Task.isCancelled else { return }
                    await self?.handleResponseTimeout(streamID: streamID, for: key)
                }
                registerActiveStream(
                    streamID: streamID,
                    requestID: requestID,
                    continuation: continuation,
                    timeoutTask: timeoutTask,
                    for: key
                )
            }
        } onCancel: {
            Task { [weak self] in
                await self?.failStream(
                    streamID: streamID,
                    for: key,
                    error: CancellationError(),
                    invalidateConnection: false
                )
            }
        }
    }

    private func invalidateConnection(for key: ConnectionKey) {
        guard var state = connectionStates[key] else { return }
        let transport = state.liveConnection?.transport
        state.liveConnection = nil
        let readerTask = state.readerTask
        state.readerTask = nil
        let idleProbeTask = state.idleProbeTask
        state.idleProbeTask = nil
        state.needsIdleProbe = false
        state.bufferedTerminalFrames.removeAll()
        if state.phase == .connected {
            state.phase = .reconnecting
        }
        connectionStates[key] = state
        inFlightConnections[key]?.cancel()
        inFlightConnections[key] = nil
        readerTask?.cancel()
        idleProbeTask?.cancel()
        if let transport {
            Task {
                await transport.close()
            }
        }
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

    private func shouldThrottleBackgroundReconnect(for key: ConnectionKey) -> Bool {
        guard let lastFailureAt = connectionStates[key]?.lastConnectionFailureAt else {
            return false
        }
        return Date().timeIntervalSince1970 - lastFailureAt < backgroundReconnectBackoffInterval
    }

    private func recordConnectionFailure(for key: ConnectionKey) {
        guard var state = connectionStates[key] else { return }
        state.lastConnectionFailureAt = Date().timeIntervalSince1970
        connectionStates[key] = state
    }

    private func clearRecordedConnectionFailure(for key: ConnectionKey) {
        guard var state = connectionStates[key] else { return }
        state.lastConnectionFailureAt = nil
        connectionStates[key] = state
    }

    private func reconnectGraceIntervalForPriority(_ priority: RequestPriority) -> TimeInterval {
        switch priority {
        case .interactive:
            return max(reconnectGraceInterval, 6)
        case .normal:
            return reconnectGraceInterval
        case .background:
            return 0
        }
    }

    private func shouldReconnectRequest(
        _ request: QueuedRequest,
        after error: MachinesAPIError,
        sentRequest: Bool,
        deadline: TimeInterval?
    ) -> Bool {
        guard shouldRetryAfterConnectionFailure(error) else {
            return false
        }
        guard let deadline else {
            return false
        }
        guard Date().timeIntervalSince1970 < deadline else {
            return false
        }
        guard request.priority != .background else {
            return false
        }
        if sentRequest {
            return Self.isOperationSafeToReplay(request.operation)
        }
        return true
    }

    nonisolated static func isOperationSafeToReplay(_ operation: MachineDataPlaneOperation) -> Bool {
        switch operation {
        case .machineListModels,
             .projectList,
             .projectSessions,
             .codexListThreads,
             .codexListMessages,
             .claudeListSessions,
             .claudeListMessages,
             .geminiListSessions,
             .geminiListMessages,
             .fsListDirectory,
             .fsGetDirectoryTree,
             .fsReadFile,
             .searchRipgrep,
             .diffDifftastic:
            return true
        default:
            return false
        }
    }

    nonisolated static func reconnectBackoffDelay(attempt: Int) -> TimeInterval {
        switch attempt {
        case 1:
            return 0.25
        case 2:
            return 0.5
        case 3:
            return 1
        default:
            return 1.5
        }
    }

    nonisolated static func reconnectGraceInterval(
        for operation: MachineDataPlaneOperation,
        baseGraceInterval: TimeInterval
    ) -> TimeInterval {
        switch RequestPriority.forOperation(operation) {
        case .interactive:
            return max(baseGraceInterval, 6)
        case .normal:
            return baseGraceInterval
        case .background:
            return 0
        }
    }

    nonisolated static func responseTimeoutInterval(
        for operation: MachineDataPlaneOperation,
        baseResponseTimeoutInterval: TimeInterval
    ) -> TimeInterval {
        switch RequestPriority.forOperation(operation) {
        case .interactive:
            return max(baseResponseTimeoutInterval, 45)
        case .normal:
            return max(baseResponseTimeoutInterval, 20)
        case .background:
            return max(min(baseResponseTimeoutInterval, 10), 5)
        }
    }

    nonisolated static func sendTimeoutInterval(
        for operation: MachineDataPlaneOperation,
        baseRequestTimeoutInterval: TimeInterval
    ) -> TimeInterval {
        switch RequestPriority.forOperation(operation) {
        case .interactive:
            return max(min(baseRequestTimeoutInterval, 6), 4)
        case .normal:
            return max(min(baseRequestTimeoutInterval, 4), 2)
        case .background:
            return max(min(baseRequestTimeoutInterval, 3), 1)
        }
    }

    private func markConnectionPhase(_ phase: ConnectionPhase, for key: ConnectionKey) {
        guard var state = connectionStates[key] else { return }
        state.phase = phase
        connectionStates[key] = state
    }

    private func registerActiveStream(
        streamID: String,
        requestID: String,
        continuation: CheckedContinuation<StreamTerminalFrame, Error>,
        timeoutTask: Task<Void, Never>,
        for key: ConnectionKey
    ) {
        guard var state = connectionStates[key] else {
            timeoutTask.cancel()
            continuation.resume(throwing: MachinesAPIError.rpcCallFailed("Machine data-plane socket is not connected"))
            return
        }
        if let bufferedFrame = state.bufferedTerminalFrames.removeValue(forKey: streamID) {
            timeoutTask.cancel()
            connectionStates[key] = state
            continuation.resume(returning: bufferedFrame)
            return
        }
        state.activeStreams[streamID] = ActiveStream(
            requestID: requestID,
            continuation: continuation,
            timeoutTask: timeoutTask
        )
        connectionStates[key] = state
    }

    private func handleResponseTimeout(streamID: String, for key: ConnectionKey) {
        failActiveStreams(for: key, error: MachinesAPIError.rpcTimedOut)
        invalidateConnection(for: key)
    }

    private func failStream(
        streamID: String,
        for key: ConnectionKey,
        error: Error,
        invalidateConnection shouldInvalidateConnection: Bool
    ) {
        guard var state = connectionStates[key],
              let activeStream = state.activeStreams.removeValue(forKey: streamID) else {
            return
        }
        activeStream.timeoutTask.cancel()
        connectionStates[key] = state
        activeStream.continuation.resume(throwing: error)
        if shouldInvalidateConnection {
            invalidateConnection(for: key)
        }
    }

    private func failActiveStreams(for key: ConnectionKey, error: Error) {
        guard var state = connectionStates[key], !state.activeStreams.isEmpty else { return }
        let activeStreams = Array(state.activeStreams.values)
        state.activeStreams.removeAll()
        state.bufferedTerminalFrames.removeAll()
        connectionStates[key] = state
        for activeStream in activeStreams {
            activeStream.timeoutTask.cancel()
            activeStream.continuation.resume(throwing: error)
        }
    }

    private func makeReaderTask(
        for key: ConnectionKey,
        transport: any MachineDataPlaneTextTransport
    ) -> Task<Void, Never> {
        Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let text = try await transport.receiveText()
                    await self?.handleIncomingFrameText(text, for: key)
                }
            } catch {
                await self?.handleReaderFailure(error, for: key)
            }
        }
    }

    private func handleIncomingFrameText(_ text: String, for key: ConnectionKey) {
        if let errorFrame = try? JSONDecoder().decode(
            MachineDataPlaneErrorFrame.self,
            from: Data(text.utf8)
        ) {
            resolveStream(
                streamID: errorFrame.streamID,
                for: key,
                frame: .error(errorFrame)
            )
            return
        }

        if let completeFrame = try? JSONDecoder().decode(
            MachineDataPlaneCompleteFrame.self,
            from: Data(text.utf8)
        ) {
            resolveStream(
                streamID: completeFrame.streamID,
                for: key,
                frame: .complete(completeFrame)
            )
        }
    }

    private func resolveStream(
        streamID: String,
        for key: ConnectionKey,
        frame: StreamTerminalFrame
    ) {
        guard var state = connectionStates[key] else {
            return
        }
        guard let activeStream = state.activeStreams.removeValue(forKey: streamID) else {
            state.bufferedTerminalFrames[streamID] = frame
            connectionStates[key] = state
            return
        }
        activeStream.timeoutTask.cancel()
        connectionStates[key] = state
        activeStream.continuation.resume(returning: frame)
    }

    private func handleReaderFailure(_ error: Error, for key: ConnectionKey) {
        guard let state = connectionStates[key],
              state.liveConnection != nil || state.readerTask != nil else {
            return
        }
        let mappedError = (error as? MachinesAPIError) ?? mapTransportError(error)
        recordConnectionFailure(for: key)
        failActiveStreams(for: key, error: mappedError)
        invalidateConnection(for: key)
    }

    private func send<T: Encodable>(
        frame: T,
        transport: any MachineDataPlaneTextTransport
    ) async throws {
        let data = try JSONEncoder().encode(frame)
        guard let text = String(data: data, encoding: .utf8) else {
            throw MachinesAPIError.invalidRPCPayload
        }
        try await transport.send(text: text)
    }

    private func requestAAD(for frame: MachineDataPlaneRequestFrame) -> Data {
        aadData([
            ("v", String(frame.v)),
            ("t", frame.t.rawValue),
            ("streamId", frame.streamID),
            ("op", frame.op.rawValue),
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

    nonisolated static func dispatchCapacity(
        maxInFlightStreams: Int?,
        activeExecutions: Int
    ) -> Int {
        let limit = max(maxInFlightStreams ?? 1, 1)
        return max(limit - max(activeExecutions, 0), 0)
    }
}

private func withMachineDataPlaneTimeout<T: Sendable>(
    _ timeoutInterval: TimeInterval,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask(operation: operation)
        group.addTask {
            let nanoseconds = UInt64(max(timeoutInterval, 0.001) * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
            throw MachinesAPIError.rpcTimedOut
        }

        guard let result = try await group.next() else {
            throw MachinesAPIError.rpcTimedOut
        }
        group.cancelAll()
        return result
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
