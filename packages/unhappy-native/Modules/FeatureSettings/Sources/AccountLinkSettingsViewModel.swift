import Foundation

@MainActor
public final class AccountLinkSettingsViewModel: ObservableObject {
    @Published public var accountSecretBase64URL: String {
        didSet {
            guard hasLoadedSecret else { return }
            scheduleSecretPersistence()
        }
    }
    @Published public private(set) var isLinking = false
    @Published public private(set) var statusMessage: String?
    @Published public private(set) var errorMessage: String?

    private let linker: any AccountLinkingAction
    private let secretStore: any AccountSecretStoring
    private var hasLoadedSecret = false
    private var persistenceTask: Task<Void, Never>?

    public init(
        linker: any AccountLinkingAction,
        secretStore: any AccountSecretStoring
    ) {
        self.linker = linker
        self.secretStore = secretStore
        self.accountSecretBase64URL = ""
    }

    deinit {
        persistenceTask?.cancel()
    }

    public func loadFromStore() async {
        guard !hasLoadedSecret else { return }
        hasLoadedSecret = false
        accountSecretBase64URL = await secretStore.loadSecretBase64URL()
        hasLoadedSecret = true
    }

    public func linkDevice(
        serverURLString: String,
        token: String,
        accountAuthURLString: String
    ) async {
        guard !isLinking else { return }
        isLinking = true
        statusMessage = nil
        errorMessage = nil
        do {
            try await linker.approveAccountLink(
                serverURLString: serverURLString,
                token: token,
                accountSecretBase64URL: accountSecretBase64URL,
                accountAuthURLString: accountAuthURLString
            )
            statusMessage = "Device linked successfully"
        } catch {
            let localized = (error as? LocalizedError)?.errorDescription
            errorMessage = localized ?? "Failed to link device"
        }
        isLinking = false
    }

    public func clearMessages() {
        statusMessage = nil
        errorMessage = nil
    }

    private func scheduleSecretPersistence() {
        let secretStore = self.secretStore
        let secretValue = self.accountSecretBase64URL.trimmingCharacters(in: .whitespacesAndNewlines)
        persistenceTask?.cancel()
        persistenceTask = Task {
            guard !Task.isCancelled else { return }
            await secretStore.setSecretBase64URL(secretValue)
        }
    }
}
