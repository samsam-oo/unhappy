import Foundation
import CoreKit

public protocol SessionsPolling: Sendable {
    func makePollingStream(
        serverURLString: String,
        token: String,
        interval: Duration
    ) async -> AsyncThrowingStream<[APISession], Error>
}

public actor SessionsPollingUseCase: SessionsPolling {
    private let loader: any SessionsLoading

    public init(loader: any SessionsLoading) {
        self.loader = loader
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
                        continuation.yield(rows.sorted { $0.updatedAt > $1.updatedAt })
                        try await Task.sleep(for: interval)
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
}
