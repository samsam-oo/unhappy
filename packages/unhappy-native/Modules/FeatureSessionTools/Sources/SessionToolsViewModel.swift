import Foundation
import CoreKit

@MainActor
public final class SessionToolsViewModel: ObservableObject {
    @Published public var filePath: String = ""
    @Published public private(set) var fileContent: String = ""
    @Published public private(set) var fileErrorMessage: String?
    @Published public private(set) var isLoadingFile = false

    @Published public private(set) var isKillingSession = false
    @Published public private(set) var killStatusMessage: String?
    @Published public private(set) var killErrorMessage: String?

    @Published public var abortReason: String = ""
    @Published public private(set) var isAbortingTask = false
    @Published public private(set) var abortStatusMessage: String?
    @Published public private(set) var abortErrorMessage: String?

    @Published public var permissionRequestID: String = ""
    @Published public var permissionDecision: APISessionPermissionDecision = .approved
    @Published public var permissionMode: APISessionPermissionMode = .default
    @Published public var permissionAllowTools: String = ""
    @Published public private(set) var isSubmittingPermission = false
    @Published public private(set) var permissionStatusMessage: String?
    @Published public private(set) var permissionErrorMessage: String?

    @Published public var switchTarget: APISessionSwitchTarget = .local
    @Published public private(set) var isSwitchingMode = false
    @Published public private(set) var switchStatusMessage: String?
    @Published public private(set) var switchErrorMessage: String?

    private let fileLoader: any SessionFileLoadingAction
    private let killer: any SessionKillAction
    private let aborter: any SessionTaskAbortAction
    private let permissionResponder: any SessionPermissionResponseAction
    private let modeSwitcher: any SessionModeSwitchAction

    public init(
        fileLoader: any SessionFileLoadingAction,
        killer: any SessionKillAction,
        aborter: any SessionTaskAbortAction,
        permissionResponder: any SessionPermissionResponseAction,
        modeSwitcher: any SessionModeSwitchAction
    ) {
        self.fileLoader = fileLoader
        self.killer = killer
        self.aborter = aborter
        self.permissionResponder = permissionResponder
        self.modeSwitcher = modeSwitcher
    }

    public func loadFile(
        sessionID: String,
        serverURLString: String,
        token: String
    ) async {
        isLoadingFile = true
        fileErrorMessage = nil
        defer { isLoadingFile = false }

        do {
            fileContent = try await fileLoader.loadFile(
                serverURLString: serverURLString,
                token: token,
                sessionID: sessionID,
                path: filePath
            )
            fileErrorMessage = nil
        } catch {
            fileContent = ""
            fileErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func killSession(
        sessionID: String,
        serverURLString: String,
        token: String
    ) async {
        isKillingSession = true
        killStatusMessage = nil
        killErrorMessage = nil
        defer { isKillingSession = false }

        do {
            let result = try await killer.killSession(
                serverURLString: serverURLString,
                token: token,
                sessionID: sessionID
            )
            killStatusMessage = result.message
            killErrorMessage = nil
        } catch {
            killStatusMessage = nil
            killErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func abortTask(
        sessionID: String,
        serverURLString: String,
        token: String
    ) async {
        isAbortingTask = true
        abortStatusMessage = nil
        abortErrorMessage = nil
        defer { isAbortingTask = false }

        do {
            _ = try await aborter.abortTask(
                serverURLString: serverURLString,
                token: token,
                sessionID: sessionID,
                reason: normalizedOptional(abortReason)
            )
            abortStatusMessage = "Abort request sent"
            abortErrorMessage = nil
        } catch {
            abortStatusMessage = nil
            abortErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func submitPermissionDecision(
        sessionID: String,
        serverURLString: String,
        token: String
    ) async {
        isSubmittingPermission = true
        permissionStatusMessage = nil
        permissionErrorMessage = nil
        defer { isSubmittingPermission = false }

        do {
            let decision = permissionDecision
            let approved = decision == .approved || decision == .approvedForSession
            _ = try await permissionResponder.respondPermission(
                serverURLString: serverURLString,
                token: token,
                sessionID: sessionID,
                permissionRequestID: permissionRequestID,
                approved: approved,
                mode: permissionMode,
                allowTools: parsedAllowTools(permissionAllowTools),
                decision: decision
            )
            permissionStatusMessage = "Permission response sent"
            permissionErrorMessage = nil
        } catch {
            permissionStatusMessage = nil
            permissionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func switchMode(
        sessionID: String,
        serverURLString: String,
        token: String
    ) async {
        isSwitchingMode = true
        switchStatusMessage = nil
        switchErrorMessage = nil
        defer { isSwitchingMode = false }

        do {
            let result = try await modeSwitcher.switchMode(
                serverURLString: serverURLString,
                token: token,
                sessionID: sessionID,
                to: switchTarget
            )
            if let switched = result.switched {
                switchStatusMessage = switched ? "Switched to \(switchTarget.rawValue)" : "No mode change"
            } else {
                switchStatusMessage = "Mode switch request sent"
            }
            switchErrorMessage = nil
        } catch {
            switchStatusMessage = nil
            switchErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private func normalizedOptional(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func parsedAllowTools(_ raw: String) -> [String]? {
    let items = raw
        .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    return items.isEmpty ? nil : items
}
