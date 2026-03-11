import Foundation
import CoreKit

public protocol DirectSessionCapabilitiesLoadingAction: Sendable {
    func loadCapabilities(
        serverURLString: String,
        token: String,
        identity: DirectSessionIdentity
    ) async throws -> APIMachineAgentCapabilities
}

public actor DirectSessionCapabilitiesLoadUseCase: DirectSessionCapabilitiesLoadingAction {
    private struct CacheKey: Hashable {
        let serverURLString: String
        let token: String
        let machineID: String
        let agent: APISessionSpawnAgent
    }

    private let service: any MachineModelsListing
    private var cachedCapabilities: [CacheKey: APIMachineAgentCapabilities] = [:]
    private var inFlightLoads: [CacheKey: Task<APIMachineAgentCapabilities, Error>] = [:]

    public init(service: any MachineModelsListing) {
        self.service = service
    }

    public func loadCapabilities(
        serverURLString: String,
        token: String,
        identity: DirectSessionIdentity
    ) async throws -> APIMachineAgentCapabilities {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw DirectSessionUseCaseError.missingToken
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw DirectSessionUseCaseError.invalidServerURL
        }

        let normalizedMachineID = identity.machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMachineID.isEmpty else {
            throw DirectSessionUseCaseError.missingMachineID
        }

        let agent: APISessionSpawnAgent
        switch identity.provider {
        case .codex:
            agent = .codex
        case .claude:
            agent = .claude
        case .gemini:
            agent = .gemini
        }

        let cacheKey = CacheKey(
            serverURLString: normalizedURL,
            token: normalizedToken,
            machineID: normalizedMachineID,
            agent: agent
        )

        if let cached = cachedCapabilities[cacheKey] {
            return cached
        }
        if let inFlight = inFlightLoads[cacheKey] {
            return try await inFlight.value
        }

        let task = Task {
            try await service.fetchAgentCapabilities(
                serverURL: serverURL,
                token: normalizedToken,
                machineID: normalizedMachineID,
                agent: agent
            )
        }
        inFlightLoads[cacheKey] = task
        defer {
            inFlightLoads[cacheKey] = nil
        }

        let capabilities = try await task.value
        cachedCapabilities[cacheKey] = capabilities
        return capabilities
    }
}
