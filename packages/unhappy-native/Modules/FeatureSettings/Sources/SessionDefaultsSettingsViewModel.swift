import Foundation
import CoreKit

@MainActor
final class SessionDefaultsSettingsViewModel: ObservableObject {
    private static let supportedAgents: [APISessionSpawnAgent] = [.codex, .claude, .gemini]

    @Published private(set) var modelOptionsByAgent: [APISessionSpawnAgent: [String]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service: any MachinesFetching & MachineModelsListing

    init(service: any MachinesFetching & MachineModelsListing = URLSessionMachinesService()) {
        self.service = service
    }

    func load(serverURLString: String, token: String) async {
        guard !isLoading else { return }

        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            modelOptionsByAgent = [:]
            errorMessage = "Sign in to load model options."
            return
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let serverURL = URL(string: normalizedURL),
              serverURL.scheme != nil,
              serverURL.host != nil else {
            modelOptionsByAgent = [:]
            errorMessage = "Valid server URL is required to load models."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let machines = try await service.fetchMachines(serverURL: serverURL, token: normalizedToken)
            guard let machine = machines.first(where: \.active) ?? machines.first else {
                modelOptionsByAgent = [:]
                errorMessage = "Connect a machine to load model options."
                return
            }

            var options: [APISessionSpawnAgent: [String]] = [:]
            try await withThrowingTaskGroup(of: (APISessionSpawnAgent, [String]).self) { group in
                for agent in Self.supportedAgents {
                    group.addTask {
                        let capabilities = try await self.service.fetchAgentCapabilities(
                            serverURL: serverURL,
                            token: normalizedToken,
                            machineID: machine.id,
                            agent: agent
                        )
                        return (agent, Self.deduplicatedModels(capabilities.models))
                    }
                }

                for try await (agent, models) in group {
                    options[agent] = models
                }
            }

            modelOptionsByAgent = options
            errorMessage = nil
        } catch {
            modelOptionsByAgent = [:]
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func modelOptions(for agent: APISessionSpawnAgent) -> [String] {
        modelOptionsByAgent[agent] ?? []
    }

    nonisolated private static func deduplicatedModels(_ values: [String]) -> [String] {
        var deduped: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !deduped.contains(trimmed) else { continue }
            deduped.append(trimmed)
        }
        return deduped
    }
}
