import Foundation
import CoreKit

public struct DaemonStatusSnapshot: Equatable, Sendable {
    public let totalMachines: Int
    public let onlineMachines: Int
    public let stoppedMachines: Int
    public let unknownMachines: Int
    public let daemonStateMachines: Int

    public init(totalMachines: Int, onlineMachines: Int, stoppedMachines: Int, unknownMachines: Int, daemonStateMachines: Int) {
        self.totalMachines = totalMachines
        self.onlineMachines = onlineMachines
        self.stoppedMachines = stoppedMachines
        self.unknownMachines = unknownMachines
        self.daemonStateMachines = daemonStateMachines
    }

    public var isReady: Bool {
        onlineMachines > 0
    }
}

public enum DaemonStatusError: LocalizedError, Equatable {
    case missingToken
    case invalidServerURL
    case failed(message: String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .invalidServerURL:
            return "Invalid server URL"
        case .failed(let message):
            return message
        }
    }
}

public protocol DaemonStatusLoadingAction: Sendable {
    func loadStatus(serverURLString: String, token: String) async throws -> DaemonStatusSnapshot
}

public actor DaemonStatusLoadUseCase: DaemonStatusLoadingAction {
    private let service: any MachinesFetching

    public init(service: any MachinesFetching) {
        self.service = service
    }

    public func loadStatus(serverURLString: String, token: String) async throws -> DaemonStatusSnapshot {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw DaemonStatusError.missingToken
        }

        let normalizedURLString = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURLString.isEmpty,
            let serverURL = URL(string: normalizedURLString),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw DaemonStatusError.invalidServerURL
        }

        do {
            let machines = try await service.fetchMachines(serverURL: serverURL, token: normalizedToken)
            let onlineMachines = machines.filter(\.active).count
            let stoppedMachines = machines.filter(\.isExplicitlyStopped).count
            let unknownMachines = machines.count - onlineMachines - stoppedMachines
            let daemonStateMachines = machines.filter { machine in
                let daemonState = machine.daemonState?.trimmingCharacters(in: .whitespacesAndNewlines)
                return daemonState?.isEmpty == false
            }.count
            return DaemonStatusSnapshot(
                totalMachines: machines.count,
                onlineMachines: onlineMachines,
                stoppedMachines: stoppedMachines,
                unknownMachines: unknownMachines,
                daemonStateMachines: daemonStateMachines
            )
        } catch {
            throw DaemonStatusError.failed(
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }
}
