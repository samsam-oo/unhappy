import Foundation
import CoreKit
import SessionKit

public protocol SessionRecentCatalogLoadingAction: Sendable {
    func loadRecentSessions(
        serverURLString: String,
        token: String
    ) async throws -> [SessionLinkedUpstreamSession]
}

public actor SessionRecentCatalogLoadUseCase: SessionRecentCatalogLoadingAction {
    private let service: any MachinesFetching & MachineRecentSessionCatalogFetching

    public init(
        service: any MachinesFetching & MachineRecentSessionCatalogFetching
    ) {
        self.service = service
    }

    public func loadRecentSessions(
        serverURLString: String,
        token: String
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

        async let machines = service.fetchMachines(serverURL: serverURL, token: normalizedToken)
        async let page = service.fetchRecentSessionCatalogPage(
            serverURL: serverURL,
            token: normalizedToken,
            limit: 200,
            cursor: nil
        )
        let (loadedMachines, loadedPage) = try await (machines, page)

        let machineMetadataByID = Dictionary(
            uniqueKeysWithValues: loadedMachines.map { machine in
                (
                    machine.id,
                    (
                        displayName: NewSessionMachinePresentation.displayName(for: machine),
                        wrappedMachineDataEncryptionKey: machine.dataEncryptionKey
                    )
                )
            }
        )

        return loadedPage.sessions.compactMap { row in
            let machineMetadata = machineMetadataByID[row.machineID]
            return SessionLinkedUpstreamSession(
                machineID: row.machineID,
                machineDisplayName: machineMetadata?.displayName ?? row.machineID,
                wrappedMachineDataEncryptionKey: machineMetadata?.wrappedMachineDataEncryptionKey,
                summary: row.summary
            )
        }
    }
}
