import Foundation
import CoreKit

public protocol MachinesLoadingAction: Sendable {
    func loadMachines(serverURLString: String, token: String) async throws -> [APIMachine]
}

public enum MachinesLoadError: LocalizedError, Equatable {
    case missingToken
    case invalidServerURL

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .invalidServerURL:
            return "Invalid server URL"
        }
    }
}

public actor MachinesLoadUseCase: MachinesLoadingAction {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
    }

    private let service: any MachinesFetching
    private var inFlightTasks: [RequestKey: Task<[APIMachine], Error>] = [:]

    public init(service: any MachinesFetching) {
        self.service = service
    }

    public func loadMachines(serverURLString: String, token: String) async throws -> [APIMachine] {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw MachinesLoadError.missingToken
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw MachinesLoadError.invalidServerURL
        }

        let key = RequestKey(serverURLString: normalizedURL, token: normalizedToken)
        if let inFlightTask = inFlightTasks[key] {
            return try await inFlightTask.value
        }

        let service = self.service
        let task = Task<[APIMachine], Error> {
            let rows = try await service.fetchMachines(serverURL: serverURL, token: normalizedToken)
            return rows.sorted { lhs, rhs in
                if lhs.active != rhs.active {
                    return lhs.active && !rhs.active
                }
                if lhs.activeAt != rhs.activeAt {
                    return lhs.activeAt > rhs.activeAt
                }
                return lhs.updatedAt > rhs.updatedAt
            }
        }

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        return try await task.value
    }
}
