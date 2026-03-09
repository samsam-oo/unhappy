import Foundation
import CoreKit

@MainActor
public final class MachinesViewModel: ObservableObject {
    @Published public private(set) var machines: [APIMachine] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?

    @Published public private(set) var spawningMachineIDs: Set<String> = []
    @Published public private(set) var updatingMachineIDs: Set<String> = []
    @Published public private(set) var stoppingMachineIDs: Set<String> = []
    @Published public private(set) var deletingMachineIDs: Set<String> = []
    @Published public private(set) var statusByMachineID: [String: String] = [:]
    @Published public private(set) var errorByMachineID: [String: String] = [:]
    @Published public private(set) var approvalDirectoryByMachineID: [String: String] = [:]
    @Published public private(set) var spawnedSessionIDByMachineID: [String: String] = [:]

    private let loader: any MachinesLoadingAction
    private let spawner: any MachineSpawnAction
    private let updater: any MachineDaemonUpdateAction
    private let stopper: any MachineDaemonStopAction
    private let deleter: any MachineDeleteAction

    public init(
        loader: any MachinesLoadingAction,
        spawner: any MachineSpawnAction,
        updater: any MachineDaemonUpdateAction,
        stopper: any MachineDaemonStopAction,
        deleter: any MachineDeleteAction
    ) {
        self.loader = loader
        self.spawner = spawner
        self.updater = updater
        self.stopper = stopper
        self.deleter = deleter
    }

    public func loadMachines(serverURLString: String, token: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            machines = try await loader.loadMachines(
                serverURLString: serverURLString,
                token: token
            )
            clearStalePerMachineState()
            errorMessage = nil
        } catch {
            machines = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func spawnSession(
        machineID: String,
        wrappedMachineDataEncryptionKey: String?,
        directory: String,
        serverURLString: String,
        token: String,
        agent: APISessionSpawnAgent = .claude,
        approvedNewDirectoryCreation: Bool = false
    ) async {
        spawningMachineIDs.insert(machineID)
        statusByMachineID[machineID] = nil
        errorByMachineID[machineID] = nil
        if approvedNewDirectoryCreation {
            approvalDirectoryByMachineID[machineID] = nil
        }
        defer { spawningMachineIDs.remove(machineID) }

        do {
            let result = try await spawner.spawnSession(
                MachineSpawnRequest(
                    serverURLString: serverURLString,
                    token: token,
                    machineID: machineID,
                    wrappedMachineDataEncryptionKey: wrappedMachineDataEncryptionKey,
                    directory: directory,
                    agent: agent,
                    approvedNewDirectoryCreation: approvedNewDirectoryCreation
                )
            )

            if let sessionID = result.sessionID, !sessionID.isEmpty {
                spawnedSessionIDByMachineID[machineID] = sessionID
                statusByMachineID[machineID] = "Spawned session \(sessionID)"
            } else {
                statusByMachineID[machineID] = "Spawned session"
            }
            errorByMachineID[machineID] = nil
            approvalDirectoryByMachineID[machineID] = nil
        } catch let error as MachineSpawnError {
            switch error {
            case .requiresUserApproval(let directory):
                approvalDirectoryByMachineID[machineID] = directory?.trimmingCharacters(in: .whitespacesAndNewlines)
                statusByMachineID[machineID] = nil
                errorByMachineID[machineID] = nil
            default:
                statusByMachineID[machineID] = nil
                errorByMachineID[machineID] = error.errorDescription ?? "Failed to spawn session"
            }
        } catch {
            statusByMachineID[machineID] = nil
            errorByMachineID[machineID] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func updateDaemon(
        machineID: String,
        serverURLString: String,
        token: String
    ) async {
        updatingMachineIDs.insert(machineID)
        statusByMachineID[machineID] = nil
        errorByMachineID[machineID] = nil
        defer { updatingMachineIDs.remove(machineID) }

        do {
            let result = try await updater.updateDaemon(
                serverURLString: serverURLString,
                token: token,
                machineID: machineID
            )
            statusByMachineID[machineID] = result.message
            errorByMachineID[machineID] = nil
        } catch {
            statusByMachineID[machineID] = nil
            errorByMachineID[machineID] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func stopDaemon(
        machineID: String,
        serverURLString: String,
        token: String
    ) async {
        stoppingMachineIDs.insert(machineID)
        statusByMachineID[machineID] = nil
        errorByMachineID[machineID] = nil
        defer { stoppingMachineIDs.remove(machineID) }

        do {
            let result = try await stopper.stopDaemon(
                serverURLString: serverURLString,
                token: token,
                machineID: machineID
            )
            machines.removeAll { $0.id == machineID }
            statusByMachineID[machineID] = result.message
            errorByMachineID[machineID] = nil
        } catch {
            statusByMachineID[machineID] = nil
            errorByMachineID[machineID] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func deleteMachine(
        machineID: String,
        serverURLString: String,
        token: String
    ) async {
        deletingMachineIDs.insert(machineID)
        statusByMachineID[machineID] = nil
        errorByMachineID[machineID] = nil
        defer { deletingMachineIDs.remove(machineID) }

        do {
            let result = try await deleter.deleteMachine(
                serverURLString: serverURLString,
                token: token,
                machineID: machineID
            )
            machines.removeAll { $0.id == machineID }
            statusByMachineID[machineID] = result.message
            errorByMachineID[machineID] = nil
            approvalDirectoryByMachineID[machineID] = nil
            spawnedSessionIDByMachineID[machineID] = nil
        } catch {
            statusByMachineID[machineID] = nil
            errorByMachineID[machineID] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func isSpawning(machineID: String) -> Bool { spawningMachineIDs.contains(machineID) }
    public func isUpdating(machineID: String) -> Bool { updatingMachineIDs.contains(machineID) }
    public func isStopping(machineID: String) -> Bool { stoppingMachineIDs.contains(machineID) }
    public func isDeleting(machineID: String) -> Bool { deletingMachineIDs.contains(machineID) }
    public func status(machineID: String) -> String? { statusByMachineID[machineID] }
    public func error(machineID: String) -> String? { errorByMachineID[machineID] }
    public func approvalDirectory(machineID: String) -> String? { approvalDirectoryByMachineID[machineID] }
    public func spawnedSessionID(machineID: String) -> String? { spawnedSessionIDByMachineID[machineID] }

    private func clearStalePerMachineState() {
        let liveMachineIDs = Set(machines.map(\.id))
        statusByMachineID = statusByMachineID.filter { liveMachineIDs.contains($0.key) }
        errorByMachineID = errorByMachineID.filter { liveMachineIDs.contains($0.key) }
        approvalDirectoryByMachineID = approvalDirectoryByMachineID.filter { liveMachineIDs.contains($0.key) }
        spawnedSessionIDByMachineID = spawnedSessionIDByMachineID.filter { liveMachineIDs.contains($0.key) }
        spawningMachineIDs = spawningMachineIDs.filter { liveMachineIDs.contains($0) }
        updatingMachineIDs = updatingMachineIDs.filter { liveMachineIDs.contains($0) }
        stoppingMachineIDs = stoppingMachineIDs.filter { liveMachineIDs.contains($0) }
        deletingMachineIDs = deletingMachineIDs.filter { liveMachineIDs.contains($0) }
    }
}
