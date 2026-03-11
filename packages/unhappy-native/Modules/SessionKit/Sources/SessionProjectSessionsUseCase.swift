import Foundation
import CoreKit

public protocol SessionProjectSessionsLoadingAction: Sendable {
    func loadProjectSessions(
        serverURLString: String,
        token: String,
        project: SessionMachineProject
    ) async throws -> [SessionLinkedUpstreamSession]
}

public actor SessionProjectSessionsLoadUseCase: SessionProjectSessionsLoadingAction {
    private let service: any MachinesFetching & MachineProjectSessionsFetching

    public init(
        service: any MachinesFetching & MachineProjectSessionsFetching
    ) {
        self.service = service
    }

    public func loadProjectSessions(
        serverURLString: String,
        token: String,
        project: SessionMachineProject
    ) async throws -> [SessionLinkedUpstreamSession] {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            return []
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            return []
        }

        let page = try await service.fetchProjectSessionsPage(
            serverURL: serverURL,
            token: normalizedToken,
            machineID: project.machineID,
            projectPath: project.summary.path,
            wrappedMachineDataEncryptionKey: project.wrappedMachineDataEncryptionKey,
            limit: 200,
            cursor: nil
        )
        if page.sessions.isEmpty,
           let error = page.error,
           !error.isEmpty {
            throw MachinesAPIError.rpcCallFailed(error)
        }

        return page.sessions.map {
            SessionLinkedUpstreamSession(
                machineID: project.machineID,
                machineDisplayName: project.machineDisplayName,
                wrappedMachineDataEncryptionKey: project.wrappedMachineDataEncryptionKey,
                summary: $0
            )
        }
    }
}
