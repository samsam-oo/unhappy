import Foundation
import Network
import OSLog

protocol MachineDataPlaneTextTransport: Sendable {
    func send(text: String) async throws
    func receiveText() async throws -> String
    func configureKeepalive(idleTimeoutSeconds: Int) async
    func close() async
}

actor MachineDataPlaneNetworkTransport: MachineDataPlaneTextTransport {
    private static let logger = Logger(
        subsystem: "im.unhappy.app",
        category: "machine-data-plane.transport"
    )

    private let url: URL
    private let token: String
    private let subprotocol: String
    private let connectTimeoutInterval: TimeInterval
    private let queue: DispatchQueue

    private var connection: NWConnection?
    private var isReady = false
    private var receiveLoopStarted = false
    private var terminalError: Error?
    private var readyContinuations: [CheckedContinuation<Void, Error>] = []
    private var receiveContinuations: [CheckedContinuation<String, Error>] = []
    private var bufferedTexts: [String] = []
    private var keepaliveTask: Task<Void, Never>?

    init(
        url: URL,
        token: String,
        subprotocol: String,
        connectTimeoutInterval: TimeInterval
    ) {
        self.url = url
        self.token = token
        self.subprotocol = subprotocol
        self.connectTimeoutInterval = connectTimeoutInterval
        self.queue = DispatchQueue(label: "im.unhappy.machine-data-plane.network.\(UUID().uuidString)")
    }

    func send(text: String) async throws {
        try await connect()
        guard let connection else {
            throw MachinesAPIError.rpcCallFailed("Machine data-plane socket is not connected")
        }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(
            identifier: UUID().uuidString,
            metadata: [metadata]
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: Data(text.utf8),
                contentContext: context,
                isComplete: true,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            )
        }
    }

    func receiveText() async throws -> String {
        try await connect()
        if let bufferedText = bufferedTexts.first {
            bufferedTexts.removeFirst()
            return bufferedText
        }
        if let terminalError {
            throw terminalError
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            receiveContinuations.append(continuation)
            startReceiveLoopIfNeeded()
        }
    }

    func configureKeepalive(idleTimeoutSeconds: Int) async {
        let interval = Self.keepaliveInterval(forIdleTimeoutSeconds: idleTimeoutSeconds)
        keepaliveTask?.cancel()
        guard interval > 0 else { return }

        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                let nanoseconds = UInt64(max(interval, 0.001) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                do {
                    try await self.sendPing()
                } catch {
                    await self.handleKeepaliveFailure(error)
                    return
                }
            }
        }
    }

    func close() async {
        terminate(with: MachinesAPIError.rpcCallFailed("Machine data-plane socket is not connected"))
    }

    nonisolated static func keepaliveInterval(forIdleTimeoutSeconds idleTimeoutSeconds: Int) -> TimeInterval {
        let idleSeconds = max(idleTimeoutSeconds, 1)
        let halfIdle = TimeInterval(idleSeconds) * 0.5
        let upperBound = TimeInterval(idleSeconds) - 5
        if upperBound >= 5 {
            return min(max(halfIdle, 5), upperBound)
        }
        return max(halfIdle, 1)
    }

    private func connect() async throws {
        if isReady { return }
        if let terminalError {
            throw terminalError
        }
        if connection == nil {
            Self.logger.log("transport connect start url=\(self.url.absoluteString, privacy: .public)")
            connection = makeConnection()
            connection?.start(queue: queue)
        }
        try await waitUntilReady()
    }

    private func makeConnection() -> NWConnection {
        let websocket = NWProtocolWebSocket.Options(.version13)
        websocket.autoReplyPing = true
        websocket.setSubprotocols([subprotocol])
        websocket.setAdditionalHeaders([
            (name: "Authorization", value: "Bearer \(token)"),
        ])

        let parameters = NWParameters(tls: NWProtocolTLS.Options(), tcp: NWProtocolTCP.Options())
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
        parameters.includePeerToPeer = false
        parameters.allowFastOpen = true

        let connection = NWConnection(to: .url(url), using: parameters)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task {
                await self.handleStateUpdate(state)
            }
        }
        return connection
    }

    private func waitUntilReady() async throws {
        if isReady { return }
        if let terminalError {
            throw terminalError
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [self] in
                try await awaitReady()
            }
            group.addTask { [self] in
                let nanos = UInt64(max(self.connectTimeoutInterval, 0.001) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanos)
                throw MachinesAPIError.rpcTimedOut
            }

            _ = try await group.next()
            group.cancelAll()
        }
    }

    private func awaitReady() async throws {
        if isReady { return }
        if let terminalError {
            throw terminalError
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            readyContinuations.append(continuation)
        }
    }

    private func startReceiveLoopIfNeeded() {
        guard !receiveLoopStarted, let connection else { return }
        receiveLoopStarted = true
        receiveNext(on: connection)
    }

    private func sendPing() async throws {
        guard isReady else { return }
        guard let connection else {
            throw MachinesAPIError.rpcCallFailed("Machine data-plane socket is not connected")
        }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .ping)
        let context = NWConnection.ContentContext(
            identifier: UUID().uuidString,
            metadata: [metadata]
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: Data(),
                contentContext: context,
                isComplete: true,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            )
        }
    }

    private func handleKeepaliveFailure(_ error: Error) {
        terminate(with: error)
    }

    private func receiveNext(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, context, _, error in
            guard let self else { return }
            Task {
                await self.handleReceivedMessage(content: content, context: context, error: error)
            }
        }
    }

    private func handleStateUpdate(_ state: NWConnection.State) {
        Self.logger.log("transport state url=\(self.url.absoluteString, privacy: .public) state=\(String(describing: state), privacy: .public)")
        if let terminalError = Self.terminalError(for: state) {
            terminate(with: terminalError)
            return
        }

        switch state {
        case .ready:
            isReady = true
            let continuations = readyContinuations
            readyContinuations.removeAll()
            for continuation in continuations {
                continuation.resume(returning: ())
            }
            startReceiveLoopIfNeeded()
        default:
            break
        }
    }

    nonisolated static func terminalError(for state: NWConnection.State) -> Error? {
        switch state {
        case .failed(let error):
            return error
        case .cancelled:
            return MachinesAPIError.rpcCallFailed("Machine data-plane socket is not connected")
        default:
            return nil
        }
    }

    private func handleReceivedMessage(
        content: Data?,
        context: NWConnection.ContentContext?,
        error: NWError?
    ) {
        if let error {
            Self.logger.error("transport receive error url=\(self.url.absoluteString, privacy: .public) error=\(String(describing: error), privacy: .public)")
            terminate(with: error)
            return
        }
        guard let connection else {
            Self.logger.error("transport receive missing-connection url=\(self.url.absoluteString, privacy: .public)")
            terminate(with: MachinesAPIError.rpcCallFailed("Machine data-plane socket is not connected"))
            return
        }

        let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
        if metadata?.opcode == .close {
            Self.logger.error("transport receive close url=\(self.url.absoluteString, privacy: .public)")
            terminate(with: MachinesAPIError.rpcCallFailed("Machine data-plane socket is not connected"))
            return
        }

        if let content,
           let text = String(data: content, encoding: .utf8) {
            if let continuation = receiveContinuations.first {
                receiveContinuations.removeFirst()
                continuation.resume(returning: text)
            } else {
                bufferedTexts.append(text)
            }
        }

        if terminalError == nil {
            receiveNext(on: connection)
        }
    }

    private func terminate(with error: Error) {
        Self.logger.error("transport terminate url=\(self.url.absoluteString, privacy: .public) error=\(String(describing: error), privacy: .public)")
        keepaliveTask?.cancel()
        keepaliveTask = nil
        terminalError = error
        isReady = false
        receiveLoopStarted = false
        connection?.cancel()
        connection = nil

        let readyContinuations = self.readyContinuations
        self.readyContinuations.removeAll()
        for continuation in readyContinuations {
            continuation.resume(throwing: error)
        }

        let receiveContinuations = self.receiveContinuations
        self.receiveContinuations.removeAll()
        for continuation in receiveContinuations {
            continuation.resume(throwing: error)
        }
    }
}
