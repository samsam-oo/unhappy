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
    @Published public private(set) var isRestoring = false
    @Published public private(set) var isRestoringByQR = false
    @Published public private(set) var qrRestoreCode: String?
    @Published public private(set) var qrRestoreProgressDots = 0
    @Published public private(set) var statusMessage: String?
    @Published public private(set) var errorMessage: String?

    private let linker: any AccountLinkingAction
    private let restorer: any AccountTokenRestoringAction
    private let qrRestorer: any AccountQRRestoringAction
    private let secretStore: any AccountSecretStoring
    private var hasLoadedSecret = false
    private var persistenceTask: Task<Void, Never>?

    public init(
        linker: any AccountLinkingAction,
        restorer: any AccountTokenRestoringAction,
        qrRestorer: any AccountQRRestoringAction,
        secretStore: any AccountSecretStoring
    ) {
        self.linker = linker
        self.restorer = restorer
        self.qrRestorer = qrRestorer
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
        guard !isLinking, !isRestoring, !isRestoringByQR else { return }
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

    public func restoreToken(serverURLString: String) async -> String? {
        guard !isRestoring, !isLinking, !isRestoringByQR else { return nil }
        isRestoring = true
        statusMessage = nil
        errorMessage = nil
        defer {
            isRestoring = false
        }

        do {
            await persistCurrentSecret()
            let token = try await restorer.restoreToken(
                serverURLString: serverURLString,
                accountSecretRaw: accountSecretBase64URL
            )
            statusMessage = "Recovered API token from secret key"
            return token
        } catch {
            let localized = (error as? LocalizedError)?.errorDescription
            errorMessage = localized ?? "Failed to restore API token"
            return nil
        }
    }

    public func restoreTokenFromQRCode(serverURLString: String) async -> String? {
        guard !isRestoringByQR, !isRestoring, !isLinking else { return nil }
        isRestoringByQR = true
        qrRestoreProgressDots = 0
        qrRestoreCode = nil
        statusMessage = nil
        errorMessage = nil
        defer {
            isRestoringByQR = false
            qrRestoreCode = nil
            qrRestoreProgressDots = 0
        }

        do {
            let session = try await qrRestorer.createSession()
            qrRestoreCode = session.qrPayload

            while true {
                try Task.checkCancellation()
                let pollResult = try await qrRestorer.pollStatus(
                    serverURLString: serverURLString,
                    session: session
                )
                switch pollResult {
                case .pending:
                    qrRestoreProgressDots = (qrRestoreProgressDots + 1) % 4
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                case .authorized(let credentials):
                    accountSecretBase64URL = credentials.secretBase64URL
                    await persistCurrentSecret()
                    statusMessage = "Recovered API token from QR approval"
                    return credentials.token
                }
            }
        } catch is CancellationError {
            statusMessage = "QR restore cancelled"
            return nil
        } catch {
            let localized = (error as? LocalizedError)?.errorDescription
            errorMessage = localized ?? "Failed to restore API token from QR"
            return nil
        }
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

    private func persistCurrentSecret() async {
        persistenceTask?.cancel()
        let secretValue = accountSecretBase64URL.trimmingCharacters(in: .whitespacesAndNewlines)
        await secretStore.setSecretBase64URL(secretValue)
    }
}
