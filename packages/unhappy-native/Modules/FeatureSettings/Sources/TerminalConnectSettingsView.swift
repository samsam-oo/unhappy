import SwiftUI
import CoreKit
#if canImport(UIKit)
import UIKit
#endif

@MainActor
struct TerminalConnectSettingsView: View {
    @StateObject private var viewModel: TerminalConnectSettingsViewModel
    @State private var authURLString = ""
    @State private var showingScanner = false
    @State private var localStatusMessage: String?
    private let serverURLString: String
    private let token: String

    init(
        serverURLString: String,
        token: String,
        makeViewModel: @escaping @MainActor () -> TerminalConnectSettingsViewModel
    ) {
        self.serverURLString = serverURLString
        self.token = token
        _viewModel = StateObject(wrappedValue: makeViewModel())
    }

    private var parsedRequest: TerminalAuthRequest? {
        TerminalAuthURLParser.parse(authURLString)
    }

    var body: some View {
        Form {
            Section("Connection URL") {
                TextField("unhappy://terminal?...", text: $authURLString, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                    .onChange(of: authURLString, initial: false) { _, _ in
                        localStatusMessage = nil
                        viewModel.resetState()
                    }

                Text("Paste the terminal auth URL from daemon or CLI.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Request Preview") {
                if let parsedRequest {
                    LabeledContent("Type") {
                        Text("Terminal Auth")
                    }
                    LabeledContent("Public Key") {
                        Text(keyPreview(for: parsedRequest.publicKey))
                            .font(.footnote.monospaced())
                    }
                } else {
                    if authURLString.isEmpty {
                        Text("Enter a URL to preview.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Invalid terminal auth URL.")
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("Request Status") {
                if viewModel.isChecking {
                    ProgressView("Checking request status...")
                } else if viewModel.isApproving {
                    ProgressView("Approving terminal request...")
                } else {
                    switch viewModel.requestState {
                    case .idle:
                        Text("No request checked yet.")
                            .foregroundStyle(.secondary)
                    case .pending(let supportsV2):
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Request is pending approval.")
                                .foregroundStyle(.orange)
                            Text("Supports V2: \(supportsV2 ? "Yes" : "No")")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    case .authorized:
                        Text("Terminal request is already authorized.")
                            .foregroundStyle(.green)
                    case .notFound:
                        Text("Request not found or expired.")
                            .foregroundStyle(.red)
                    case .failed(let message):
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("Actions") {
                Button("Scan QR Code") {
                    showingScanner = true
                }
                .disabled(viewModel.isChecking || viewModel.isApproving)

                Button("Paste from Clipboard") {
                    pasteFromClipboard()
                }
                .disabled(viewModel.isChecking || viewModel.isApproving)

                Button("Check Request") {
                    guard let publicKey = parsedRequest?.publicKey else { return }
                    Task {
                        await viewModel.checkRequest(
                            serverURLString: serverURLString,
                            publicKeyBase64URL: publicKey
                        )
                    }
                }
                .disabled(parsedRequest == nil || viewModel.isChecking || viewModel.isApproving)

                Button("Approve Terminal") {
                    guard let publicKey = parsedRequest?.publicKey else { return }
                    Task {
                        await viewModel.approveRequest(
                            serverURLString: serverURLString,
                            token: token,
                            publicKeyBase64URL: publicKey
                        )
                    }
                }
                .disabled(
                    parsedRequest == nil
                        || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || viewModel.isChecking
                        || viewModel.isApproving
                )

                Button("Copy Public Key") {
                    guard let publicKey = parsedRequest?.publicKey else { return }
                    copyToClipboard(publicKey)
                    localStatusMessage = "Copied public key"
                }
                .disabled(parsedRequest == nil)

                if token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Set API token first in Settings > Account.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if let localStatusMessage {
                    Text(localStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
                if let statusMessage = viewModel.statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }

            Section("Notes") {
                Text("Native terminal approval uses daemon request status and encrypted approval response. QR scanner is available on supported iOS devices.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Terminal Connect")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingScanner) {
            TerminalQRScannerSheet { scannedValue in
                applyScannedAuthURL(scannedValue)
            }
        }
    }

    private func keyPreview(for key: String) -> String {
        if key.count <= 20 {
            return key
        }
        return "\(key.prefix(12))...\(key.suffix(8))"
    }

    private func pasteFromClipboard() {
#if canImport(UIKit)
        let rawValue = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawValue.isEmpty else {
            localStatusMessage = "Clipboard is empty"
            return
        }
        applyScannedAuthURL(rawValue)
#endif
    }

    private func applyScannedAuthURL(_ rawValue: String) {
        authURLString = rawValue
        localStatusMessage = "Loaded URL"

        guard let publicKey = TerminalAuthURLParser.parse(rawValue)?.publicKey else {
            localStatusMessage = "Scanned code is not a terminal auth URL"
            return
        }

        Task {
            await viewModel.checkRequest(
                serverURLString: serverURLString,
                publicKeyBase64URL: publicKey
            )
        }
    }
}

#Preview {
    TerminalConnectSettingsView(
        serverURLString: "https://api.unhappy.im",
        token: "token",
        makeViewModel: {
            TerminalConnectSettingsViewModel(
                connector: TerminalConnectUseCase(
                    service: URLSessionTerminalAuthService(),
                    dataKeyStore: UserDefaultsTerminalDataKeyStore(),
                    encryptor: TweetNaclTerminalAuthEncryptor()
                )
            )
        }
    )
}

private func copyToClipboard(_ value: String) {
#if canImport(UIKit)
    UIPasteboard.general.string = value
#endif
}
