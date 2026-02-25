import Foundation
import CoreKit

@MainActor
public final class NewSessionViewModel: ObservableObject {
    @Published public private(set) var machines: [APIMachine] = []
    @Published public private(set) var isLoadingMachines = false
    @Published public private(set) var isLoadingDirectory = false
    @Published public private(set) var isSpawning = false
    @Published public private(set) var directoryEntries: [APIMachineDirectoryEntry] = []
    @Published public private(set) var selectedMachineID: String?
    @Published public var directoryPath: String = "~"
    @Published public var selectedAgent: APISessionSpawnAgent = .claude
    @Published public var codexResumeThreadID: String = ""
    @Published public var claudeResumeSessionID: String = ""
    @Published public var sessionToken: String = ""
    @Published public var environmentVariablesText: String = ""
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var infoMessage: String?
    @Published public private(set) var approvalDirectory: String?
    @Published public private(set) var spawnedSessionID: String?

    private let machinesLoader: any NewSessionMachinesLoadingAction
    private let directoryLister: any NewSessionDirectoryListingAction
    private let spawner: any NewSessionSpawningAction

    public init(
        machinesLoader: any NewSessionMachinesLoadingAction,
        directoryLister: any NewSessionDirectoryListingAction,
        spawner: any NewSessionSpawningAction
    ) {
        self.machinesLoader = machinesLoader
        self.directoryLister = directoryLister
        self.spawner = spawner
    }

    public func loadMachines(serverURLString: String, token: String) async {
        isLoadingMachines = true
        errorMessage = nil
        defer { isLoadingMachines = false }

        do {
            let loaded = try await machinesLoader.loadMachines(
                serverURLString: serverURLString,
                token: token
            )
            machines = loaded
            if selectedMachineID == nil {
                selectedMachineID = loaded.first?.id
            } else if let selectedMachineID, loaded.contains(where: { $0.id == selectedMachineID }) == false {
                self.selectedMachineID = loaded.first?.id
            }

            if self.selectedMachineID != nil {
                await loadDirectory(serverURLString: serverURLString, token: token)
            } else {
                directoryEntries = []
            }
        } catch {
            machines = []
            directoryEntries = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func selectMachine(
        _ machineID: String,
        serverURLString: String,
        token: String
    ) async {
        selectedMachineID = machineID
        approvalDirectory = nil
        spawnedSessionID = nil
        infoMessage = nil
        await loadDirectory(serverURLString: serverURLString, token: token)
    }

    public func loadDirectory(serverURLString: String, token: String) async {
        guard let machineID = selectedMachineID else {
            directoryEntries = []
            return
        }

        let path = normalizedPath(directoryPath)
        directoryPath = path
        isLoadingDirectory = true
        errorMessage = nil
        defer { isLoadingDirectory = false }

        do {
            directoryEntries = try await directoryLister.listDirectory(
                serverURLString: serverURLString,
                token: token,
                machineID: machineID,
                path: path
            )
        } catch {
            directoryEntries = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func selectDirectoryEntry(
        _ entry: APIMachineDirectoryEntry,
        serverURLString: String,
        token: String
    ) async {
        guard entry.type == "directory" else { return }
        directoryPath = resolvedPath(current: directoryPath, entryName: entry.name)
        await loadDirectory(serverURLString: serverURLString, token: token)
    }

    public func startSession(serverURLString: String, token: String) async -> Bool {
        await spawn(
            serverURLString: serverURLString,
            token: token,
            directory: directoryPath,
            approvedNewDirectoryCreation: false
        )
    }

    public func continueWithDirectoryApproval(serverURLString: String, token: String) async -> Bool {
        guard let approvalDirectory else { return false }
        return await spawn(
            serverURLString: serverURLString,
            token: token,
            directory: approvalDirectory,
            approvedNewDirectoryCreation: true
        )
    }

    private func spawn(
        serverURLString: String,
        token: String,
        directory: String,
        approvedNewDirectoryCreation: Bool
    ) async -> Bool {
        let environmentVariables: [String: String]
        do {
            environmentVariables = try NewSessionEnvironmentVariablesParser.parse(environmentVariablesText)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }

        guard let machineID = selectedMachineID else {
            errorMessage = NewSessionError.missingMachineID.errorDescription
            return false
        }

        isSpawning = true
        errorMessage = nil
        infoMessage = nil
        spawnedSessionID = nil
        if approvedNewDirectoryCreation {
            approvalDirectory = nil
        }
        defer { isSpawning = false }

        do {
            let result = try await spawner.spawnSession(
                serverURLString: serverURLString,
                token: token,
                machineID: machineID,
                directory: directory,
                agent: selectedAgent,
                approvedNewDirectoryCreation: approvedNewDirectoryCreation,
                codexResumeThreadID: codexResumeThreadID,
                claudeResumeSessionID: claudeResumeSessionID,
                sessionToken: sessionToken,
                environmentVariables: environmentVariables
            )
            let sessionID = result.sessionID?.trimmingCharacters(in: .whitespacesAndNewlines)
            spawnedSessionID = (sessionID?.isEmpty == false) ? sessionID : nil
            if let spawnedSessionID {
                infoMessage = "Spawned session \(spawnedSessionID)"
            } else {
                infoMessage = "Spawned session"
            }
            approvalDirectory = nil
            errorMessage = nil
            return true
        } catch let error as NewSessionError {
            if case .requiresUserApproval(let directory) = error {
                approvalDirectory = normalizedOptionalPath(directory)
                errorMessage = nil
                infoMessage = nil
                return false
            }
            approvalDirectory = nil
            infoMessage = nil
            errorMessage = error.errorDescription ?? "Failed to spawn session"
            return false
        } catch {
            approvalDirectory = nil
            infoMessage = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}

private func normalizedPath(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "~" : trimmed
}

private func normalizedOptionalPath(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func resolvedPath(current: String, entryName: String) -> String {
    let path = normalizedPath(current)
    let trimmedName = entryName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { return path }
    if trimmedName == "." {
        return path
    }
    if trimmedName == ".." {
        if path == "~" {
            return "~"
        }
        if path.hasPrefix("~/") {
            let suffix = String(path.dropFirst(2))
            let components = suffix.split(separator: "/").dropLast()
            if components.isEmpty {
                return "~"
            }
            return "~/" + components.joined(separator: "/")
        }
        if path == "/" {
            return "/"
        }
        let components = path.split(separator: "/").dropLast()
        if components.isEmpty {
            return "/"
        }
        return "/" + components.joined(separator: "/")
    }
    if trimmedName.hasPrefix("/") {
        return trimmedName
    }
    if path == "/" {
        return "/" + trimmedName
    }
    if path.hasSuffix("/") {
        return path + trimmedName
    }
    if path == "~" {
        return "~/" + trimmedName
    }
    return path + "/" + trimmedName
}
