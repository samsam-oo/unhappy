import Foundation
import Testing
@testable import FeatureSettings

@MainActor
struct TerminalConnectSettingsViewModelTests {
    @Test
    func checkRequestUpdatesPendingState() async {
        let connector = MockTerminalConnector(
            checkState: .pending(supportsV2: true),
            approveState: .authorized
        )
        let viewModel = TerminalConnectSettingsViewModel(connector: connector)

        await viewModel.checkRequest(
            serverURLString: "https://api.unhappy.im",
            publicKeyBase64URL: "public-key"
        )

        #expect(viewModel.requestState == .pending(supportsV2: true))
        #expect(viewModel.statusMessage == nil)
        #expect(viewModel.isChecking == false)
    }

    @Test
    func checkRequestMapsNotFoundErrorState() async {
        let connector = MockTerminalConnector(
            checkError: .requestNotFound,
            approveState: .authorized
        )
        let viewModel = TerminalConnectSettingsViewModel(connector: connector)

        await viewModel.checkRequest(
            serverURLString: "https://api.unhappy.im",
            publicKeyBase64URL: "public-key"
        )

        #expect(viewModel.requestState == .notFound)
        #expect(viewModel.statusMessage == nil)
    }

    @Test
    func approveRequestUpdatesAuthorizedStateAndStatusMessage() async {
        let connector = MockTerminalConnector(
            checkState: .pending(supportsV2: true),
            approveState: .authorized
        )
        let viewModel = TerminalConnectSettingsViewModel(connector: connector)

        await viewModel.approveRequest(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            publicKeyBase64URL: "public-key"
        )

        #expect(viewModel.requestState == .authorized)
        #expect(viewModel.statusMessage == "Terminal request approved")
        #expect(viewModel.isApproving == false)
    }

    @Test
    func approveRequestMapsValidationErrorState() async {
        let connector = MockTerminalConnector(
            checkState: .pending(supportsV2: true),
            approveError: .invalidPublicKey
        )
        let viewModel = TerminalConnectSettingsViewModel(connector: connector)

        await viewModel.approveRequest(
            serverURLString: "https://api.unhappy.im",
            token: "token",
            publicKeyBase64URL: "public-key"
        )

        #expect(viewModel.requestState == .failed(message: "Invalid terminal public key"))
        #expect(viewModel.statusMessage == nil)
    }
}

private actor MockTerminalConnector: TerminalConnectingAction {
    private let checkState: TerminalConnectRequestState
    private let checkError: TerminalConnectError?
    private let approveState: TerminalConnectRequestState
    private let approveError: TerminalConnectError?

    init(
        checkState: TerminalConnectRequestState = .pending(supportsV2: false),
        checkError: TerminalConnectError? = nil,
        approveState: TerminalConnectRequestState = .authorized,
        approveError: TerminalConnectError? = nil
    ) {
        self.checkState = checkState
        self.checkError = checkError
        self.approveState = approveState
        self.approveError = approveError
    }

    func fetchRequestState(
        serverURLString: String,
        publicKeyBase64URL: String
    ) async throws -> TerminalConnectRequestState {
        if let checkError {
            throw checkError
        }
        return checkState
    }

    func approveRequest(
        serverURLString: String,
        token: String,
        publicKeyBase64URL: String
    ) async throws -> TerminalConnectRequestState {
        if let approveError {
            throw approveError
        }
        return approveState
    }
}
