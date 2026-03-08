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
    private let service: any MachineModelsListing

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

        return try await service.fetchAgentCapabilities(
            serverURL: serverURL,
            token: normalizedToken,
            machineID: normalizedMachineID,
            agent: agent
        )
    }
}
