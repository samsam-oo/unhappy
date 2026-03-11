import Foundation
import CoreKit
import SessionKit

public protocol SessionsPolling: Sendable {
    func makePollingStream(
        serverURLString: String,
        token: String,
        interval: Duration
    ) async -> AsyncThrowingStream<[APISession], Error>
}

public actor SessionsPollingUseCase: SessionsPolling {
    private let loader: any SessionsLoading
    private let activeInterval: Duration

    public init(
        loader: any SessionsLoading,
        activeInterval: Duration = .seconds(4)
    ) {
        self.loader = loader
        self.activeInterval = activeInterval
    }

    public func makePollingStream(
        serverURLString: String,
        token: String,
        interval: Duration = .seconds(20)
    ) async -> AsyncThrowingStream<[APISession], Error> {
        let loader = self.loader

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    while !Task.isCancelled {
                        let rows = try await loader.loadSessions(
                            serverURLString: serverURLString,
                            token: token
                        )
                        let sortedRows = rows.sorted { $0.updatedAt > $1.updatedAt }
                        continuation.yield(sortedRows)
                        try await Task.sleep(for: sleepInterval(for: sortedRows, idleInterval: interval))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func sleepInterval(
        for rows: [APISession],
        idleInterval: Duration
    ) -> Duration {
        guard rows.contains(where: shouldPollAggressively) else {
            return idleInterval
        }
        return activeInterval
    }

    private func shouldPollAggressively(_ session: APISession) -> Bool {
        if session.active {
            return true
        }

        let agentState = SessionPayloadValueResolver.decodeJSONObject(
            payload: session.agentState,
            dataEncryptionKey: session.dataEncryptionKey
        )
        let metadata = SessionPayloadValueResolver.decodeJSONObject(
            payload: session.metadata,
            dataEncryptionKey: session.dataEncryptionKey
        )
        return SessionApprovalStateEvaluator.hasPendingApprovalRequest(
            agentState: agentState,
            metadata: metadata
        )
    }
}
