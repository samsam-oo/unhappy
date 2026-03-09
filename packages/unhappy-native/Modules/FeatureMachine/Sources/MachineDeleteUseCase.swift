import Foundation
import CoreKit

public protocol MachineDeleteAction: Sendable {
    func deleteMachine(serverURLString: String, token: String, machineID: String) async throws -> APIMachineCommandResult
}

public actor MachineDeleteUseCase: MachineDeleteAction {
    private let service: any MachineDeleting

    public init(service: any MachineDeleting) {
        self.service = service
    }

    public func deleteMachine(serverURLString: String, token: String, machineID: String) async throws -> APIMachineCommandResult {
        let (serverURL, normalizedToken, normalizedMachineID) = try normalizeInputs(
            serverURLString: serverURLString,
            token: token,
            machineID: machineID
        )

        let result = try await service.deleteMachine(
            serverURL: serverURL,
            token: normalizedToken,
            machineID: normalizedMachineID
        )
        if result.success {
            return result
        }
        let normalizedError = result.error?.trimmingCharacters(in: .whitespacesAndNewlines)
        throw MachineDaemonError.failed(
            message: (normalizedError?.isEmpty == false ? normalizedError : nil) ?? result.message
        )
    }
}
