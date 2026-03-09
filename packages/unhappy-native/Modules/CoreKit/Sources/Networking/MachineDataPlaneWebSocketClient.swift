import Foundation
import SecurityKit

public actor MachineDataPlaneWebSocketClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
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
            rawWrappedKey: wrappedMachineDataEncryptionKey,
            machineID: machineID
        ) else {
            throw MachinesAPIError.rpcCallFailed("Machine data encryption key is unavailable")
        }

        let task = try makeTask(serverURL: serverURL, token: token, machineID: machineID)
        task.resume()
        defer {
            task.cancel(with: .goingAway, reason: nil)
        }

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

        let streamID = UUID().uuidString
        let requestHeader = MachineDataPlaneRequestFrame(
            streamID: streamID,
            op: operation,
            body: MachineDataPlaneSealedBody(nonce: "", ciphertext: "", tag: ""),
            expectsChunks: false
        )
        let sealedBody = try MachineDataPlaneEncryption.encryptDataPlaneJSONObject(
            bodyObject,
            sessionKey: sessionKey,
            authenticatedData: requestAAD(for: requestHeader)
        )
        let requestFrame = MachineDataPlaneRequestFrame(
            streamID: streamID,
            op: operation,
            body: MachineDataPlaneSealedBody(
                nonce: sealedBody.nonce,
                ciphertext: sealedBody.ciphertext,
                tag: sealedBody.tag
            ),
            expectsChunks: false
        )
        try await send(frame: requestFrame, task: task)

        while true {
            let message = try await task.receive()
            guard case .string(let text) = message else { continue }
            if let errorFrame = try? JSONDecoder().decode(MachineDataPlaneErrorFrame.self, from: Data(text.utf8)),
               errorFrame.streamID == streamID {
                throw MachinesAPIError.rpcCallFailed(errorFrame.message)
            }
            if let completeFrame = try? JSONDecoder().decode(MachineDataPlaneCompleteFrame.self, from: Data(text.utf8)),
               completeFrame.streamID == streamID {
                let decrypted = try MachineDataPlaneEncryption.decryptDataPlanePayload(
                    MachineDataPlaneSealedPayload(
                        nonce: completeFrame.body.nonce,
                        ciphertext: completeFrame.body.ciphertext,
                        tag: completeFrame.body.tag
                    ),
                    sessionKey: sessionKey,
                    authenticatedData: completeAAD(for: completeFrame)
                )
                return decrypted
            }
        }
    }

    private func makeTask(serverURL: URL, token: String, machineID: String) throws -> URLSessionWebSocketTask {
        guard let url = dataPlaneURL(serverURL: serverURL, machineID: machineID) else {
            throw MachinesAPIError.invalidRPCPayload
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(MachineDataPlaneProtocol.subprotocol, forHTTPHeaderField: "Sec-WebSocket-Protocol")
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
