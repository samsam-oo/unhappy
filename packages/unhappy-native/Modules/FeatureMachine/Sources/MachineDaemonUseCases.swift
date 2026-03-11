import Foundation
import CoreKit

public protocol MachineDaemonStopAction: Sendable {
    func stopDaemon(serverURLString: String, token: String, machineID: String) async throws -> APIMachineCommandResult
}

public protocol MachineDaemonUpdateAction: Sendable {
    func updateDaemon(serverURLString: String, token: String, machineID: String) async throws -> APIMachineCommandResult
}

public protocol MachineDaemonPreventSleepAction: Sendable {
    func setPreventSleep(
        serverURLString: String,
        token: String,
        machineID: String,
        enabled: Bool
    ) async throws -> APIMachineCommandResult
}

public enum MachineDaemonError: LocalizedError, Equatable {
    case missingToken
    case invalidServerURL
    case missingMachineID
    case failed(message: String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .invalidServerURL:
            return "Invalid server URL"
        case .missingMachineID:
            return "Machine ID is required"
        case .failed(let message):
            return message
        }
    }
}

public actor MachineDaemonStopUseCase: MachineDaemonStopAction {
    private let service: any MachineDaemonStopping

    public init(service: any MachineDaemonStopping) {
        self.service = service
    }

    public func stopDaemon(serverURLString: String, token: String, machineID: String) async throws -> APIMachineCommandResult {
        let (serverURL, normalizedToken, normalizedMachineID) = try normalizeInputs(
            serverURLString: serverURLString,
            token: token,
            machineID: machineID
        )

        let result = try await service.stopDaemon(
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

public actor MachineDaemonUpdateUseCase: MachineDaemonUpdateAction {
    private let service: any MachineDaemonUpdating

    public init(service: any MachineDaemonUpdating) {
        self.service = service
    }

    public func updateDaemon(serverURLString: String, token: String, machineID: String) async throws -> APIMachineCommandResult {
        let (serverURL, normalizedToken, normalizedMachineID) = try normalizeInputs(
            serverURLString: serverURLString,
            token: token,
            machineID: machineID
        )

        let result = try await service.updateDaemon(
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

public actor MachineDaemonPreventSleepUseCase: MachineDaemonPreventSleepAction {
    private let service: any MachineDaemonPreventSleepSetting

    public init(service: any MachineDaemonPreventSleepSetting) {
        self.service = service
    }

    public func setPreventSleep(
        serverURLString: String,
        token: String,
        machineID: String,
        enabled: Bool
    ) async throws -> APIMachineCommandResult {
        let (serverURL, normalizedToken, normalizedMachineID) = try normalizeInputs(
            serverURLString: serverURLString,
            token: token,
            machineID: machineID
        )

        let result = try await service.setDaemonPreventSleep(
            serverURL: serverURL,
            token: normalizedToken,
            machineID: normalizedMachineID,
            enabled: enabled
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

func normalizeInputs(
    serverURLString: String,
    token: String,
    machineID: String
) throws -> (URL, String, String) {
    let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedToken.isEmpty else {
        throw MachineDaemonError.missingToken
    }

    let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
        !normalizedURL.isEmpty,
        let serverURL = URL(string: normalizedURL),
        serverURL.scheme != nil,
        serverURL.host != nil
    else {
        throw MachineDaemonError.invalidServerURL
    }

    let normalizedMachineID = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedMachineID.isEmpty else {
        throw MachineDaemonError.missingMachineID
    }

    return (serverURL, normalizedToken, normalizedMachineID)
}
