import Foundation

@MainActor
public final class TerminalConnectSettingsViewModel: ObservableObject {
    @Published public private(set) var requestState: TerminalConnectRequestUIState = .idle
    @Published public private(set) var isChecking = false
    @Published public private(set) var isApproving = false
    @Published public private(set) var statusMessage: String?

    private let connector: any TerminalConnectingAction

    public init(connector: any TerminalConnectingAction) {
        self.connector = connector
    }

    public func resetState() {
        requestState = .idle
        statusMessage = nil
    }

    public func checkRequest(serverURLString: String, publicKeyBase64URL: String) async {
        isChecking = true
        defer { isChecking = false }

        do {
            let state = try await connector.fetchRequestState(
                serverURLString: serverURLString,
                publicKeyBase64URL: publicKeyBase64URL
            )
            requestState = mapState(state)
            statusMessage = nil
        } catch let error as TerminalConnectError {
            apply(error: error)
        } catch {
            requestState = .failed(message: error.localizedDescription)
        }
    }

    public func approveRequest(serverURLString: String, token: String, publicKeyBase64URL: String) async {
        isApproving = true
        defer { isApproving = false }

        do {
            let state = try await connector.approveRequest(
                serverURLString: serverURLString,
                token: token,
                publicKeyBase64URL: publicKeyBase64URL
            )
            requestState = mapState(state)
            statusMessage = "Terminal request approved"
        } catch let error as TerminalConnectError {
            apply(error: error)
        } catch {
            requestState = .failed(message: error.localizedDescription)
        }
    }

    private func mapState(_ state: TerminalConnectRequestState) -> TerminalConnectRequestUIState {
        switch state {
        case .pending(let supportsV2):
            return .pending(supportsV2: supportsV2)
        case .authorized:
            return .authorized
        }
    }

    private func apply(error: TerminalConnectError) {
        switch error {
        case .requestNotFound:
            requestState = .notFound
        default:
            requestState = .failed(message: error.errorDescription ?? "Failed to process terminal request")
        }
        statusMessage = nil
    }
}

public enum TerminalConnectRequestUIState: Equatable {
    case idle
    case pending(supportsV2: Bool)
    case authorized
    case notFound
    case failed(message: String)
}
