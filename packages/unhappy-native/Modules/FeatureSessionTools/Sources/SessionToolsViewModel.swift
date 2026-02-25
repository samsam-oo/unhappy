import Foundation

@MainActor
public final class SessionToolsViewModel: ObservableObject {
    @Published public var filePath: String = ""
    @Published public private(set) var fileContent: String = ""
    @Published public private(set) var fileErrorMessage: String?
    @Published public private(set) var isLoadingFile = false

    @Published public private(set) var isKillingSession = false
    @Published public private(set) var killStatusMessage: String?
    @Published public private(set) var killErrorMessage: String?

    private let fileLoader: any SessionFileLoadingAction
    private let killer: any SessionKillAction

    public init(
        fileLoader: any SessionFileLoadingAction,
        killer: any SessionKillAction
    ) {
        self.fileLoader = fileLoader
        self.killer = killer
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
}
