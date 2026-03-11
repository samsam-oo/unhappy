import Foundation
import CoreKit

enum SessionLoadTimeout {
    static let directMessages: Duration = .seconds(6)
    static let projects: Duration = .seconds(4)
    static let upstreamSessions: Duration = .seconds(5)
}

func withSessionLoadTimeout<T: Sendable>(
    _ timeout: Duration,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask(operation: operation)
        group.addTask {
            try await Task.sleep(for: timeout)
            throw MachinesAPIError.rpcTimedOut
        }

        guard let result = try await group.next() else {
            throw MachinesAPIError.rpcTimedOut
        }
        group.cancelAll()
        return result
    }
}
