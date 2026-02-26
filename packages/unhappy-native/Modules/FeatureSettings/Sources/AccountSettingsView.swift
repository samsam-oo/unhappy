import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
struct AccountSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var accountLinkViewModel: AccountLinkSettingsViewModel
    @State private var accountAuthURLString = ""
    @State private var showingScanner = false
    @State private var statusMessage: String?
    @State private var qrRestoreTask: Task<Void, Never>?

    init(
        viewModel: SettingsViewModel,
        makeAccountLinkViewModel: @escaping @MainActor () -> AccountLinkSettingsViewModel
    ) {
        self.viewModel = viewModel
        _accountLinkViewModel = StateObject(wrappedValue: makeAccountLinkViewModel())
    }

    private var parsedAccountRequest: AccountAuthRequest? {
        AccountAuthURLParser.parse(accountAuthURLString)
    }

    private var parsedTerminalRequest: TerminalAuthRequest? {
        TerminalAuthURLParser.parse(accountAuthURLString)
    }

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("API Token") {
                    Text(hasToken ? "Configured" : "Missing")
                        .foregroundStyle(hasToken ? .green : .secondary)
                }
                LabeledContent("Server") {
                    Text(viewModel.serverURLString)
                        .font(.footnote.monospaced())
                        .lineLimit(1)
                }
                LabeledContent("Token") {
                    Text(maskedToken)
                        .font(.footnote.monospaced())
                }
            }

            Section("Link New Device") {
                TextField("unhappy://account?...", text: $accountAuthURLString, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                    .onChange(of: accountAuthURLString, initial: false) { _, _ in
                        statusMessage = nil
                        accountLinkViewModel.clearMessages()
                    }
                SecureField("Account Secret (base64url)", text: $accountLinkViewModel.accountSecretBase64URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                if let parsedAccountRequest {
                    LabeledContent("Public Key") {
                        Text(keyPreview(for: parsedAccountRequest.publicKey))
                            .font(.footnote.monospaced())
                    }
                } else if parsedTerminalRequest != nil {
                    Text("This is a terminal auth URL. Use Settings > Terminal to approve terminal requests.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                } else if !accountAuthURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Invalid account auth URL.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if accountLinkViewModel.isLinking {
                    ProgressView("Linking device...")
                } else if accountLinkViewModel.isRestoring {
                    ProgressView("Restoring token from secret...")
                } else if accountLinkViewModel.isRestoringByQR {
                    ProgressView(
                        "Waiting for QR approval\(String(repeating: ".", count: accountLinkViewModel.qrRestoreProgressDots))"
                    )
                }
                if let statusMessage = accountLinkViewModel.statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
                if let errorMessage = accountLinkViewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Restore With QR") {
                Text("Open Unhappy on another device and approve the restore request by scanning this QR.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let qrCode = accountLinkViewModel.qrRestoreCode {
                    HStack {
                        Spacer()
                        QRCodeImageView(content: qrCode, size: 220)
                        Spacer()
                    }
                }
            }

            Section("Actions") {
                Button("Scan Account QR") {
                    showingScanner = true
                }
                .disabled(
                    accountLinkViewModel.isLinking
                        || accountLinkViewModel.isRestoring
                        || accountLinkViewModel.isRestoringByQR
                )

                Button("Paste Account URL") {
                    pasteFromClipboard()
                }
                .disabled(
                    accountLinkViewModel.isLinking
                        || accountLinkViewModel.isRestoring
                        || accountLinkViewModel.isRestoringByQR
                )

                Button("Link Device") {
                    Task {
                        await accountLinkViewModel.linkDevice(
                            serverURLString: viewModel.serverURLString,
                            token: viewModel.apiToken,
                            accountAuthURLString: accountAuthURLString
                        )
                    }
                }
                .disabled(
                    parsedAccountRequest == nil
                        || !hasToken
                        || accountLinkViewModel.accountSecretBase64URL
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                        || accountLinkViewModel.isLinking
                        || accountLinkViewModel.isRestoring
                        || accountLinkViewModel.isRestoringByQR
                )

                Button("Restore Token From Secret") {
                    Task {
                        if let restoredToken = await accountLinkViewModel.restoreToken(
                            serverURLString: viewModel.serverURLString
                        ) {
                            viewModel.apiToken = restoredToken
                            statusMessage = "Restored API token"
                        }
                    }
                }
                .disabled(
                    accountLinkViewModel.accountSecretBase64URL
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                        || accountLinkViewModel.isLinking
                        || accountLinkViewModel.isRestoring
                        || accountLinkViewModel.isRestoringByQR
                )

                Button("Start QR Restore") {
                    qrRestoreTask?.cancel()
                    qrRestoreTask = Task {
                        defer { qrRestoreTask = nil }
                        if let restoredToken = await accountLinkViewModel.restoreTokenFromQRCode(
                            serverURLString: viewModel.serverURLString
                        ) {
                            viewModel.apiToken = restoredToken
                            statusMessage = "Restored API token from QR"
                        }
                    }
                }
                .disabled(
                    accountLinkViewModel.isLinking
                        || accountLinkViewModel.isRestoring
                        || accountLinkViewModel.isRestoringByQR
                )

                Button("Cancel QR Restore", role: .cancel) {
                    qrRestoreTask?.cancel()
                    qrRestoreTask = nil
                }
                .disabled(!accountLinkViewModel.isRestoringByQR)

                Button("Copy API Token") {
                    copyToClipboard(viewModel.apiToken)
                    statusMessage = "Copied API token"
                }
                .disabled(!hasToken)

                Button("Clear API Token", role: .destructive) {
                    viewModel.apiToken = ""
                    statusMessage = "Cleared API token"
                }
                .disabled(!hasToken)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }

            Section("Notes") {
                Text("Completion status is daemon-based. Check Settings > Connectors for daemon running state.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Account QR link uses API token + account secret key to approve device pairing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingScanner) {
            TerminalQRScannerSheet { scannedValue in
                applyScannedAccountURL(scannedValue)
            }
        }
        .task {
            await accountLinkViewModel.loadFromStore()
        }
        .onDisappear {
            qrRestoreTask?.cancel()
            qrRestoreTask = nil
        }
    }

    private var hasToken: Bool {
        !viewModel.apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var maskedToken: String {
        let token = viewModel.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return "None" }
        if token.count <= 10 {
            return "••••••••"
        }
        return "\(token.prefix(4))…\(token.suffix(4))"
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
            statusMessage = "Clipboard is empty"
            return
        }
        applyScannedAccountURL(rawValue)
#endif
    }

    private func applyScannedAccountURL(_ rawValue: String) {
        accountAuthURLString = rawValue
        if parsedAccountRequest != nil {
            statusMessage = "Loaded account URL"
        } else if parsedTerminalRequest != nil {
            statusMessage = "Loaded terminal URL. Open Settings > Terminal."
        } else {
            statusMessage = "Loaded URL"
        }
        accountLinkViewModel.clearMessages()
    }
}

private func copyToClipboard(_ value: String) {
#if canImport(UIKit)
    UIPasteboard.general.string = value
#endif
}
