import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public struct AccountRestoreView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var accountLinkViewModel: AccountLinkSettingsViewModel
    @State private var localStatusMessage: String?
    @State private var qrRestoreTask: Task<Void, Never>?

    public init(
        viewModel: SettingsViewModel,
        makeAccountLinkViewModel: @escaping @MainActor () -> AccountLinkSettingsViewModel
    ) {
        self.viewModel = viewModel
        _accountLinkViewModel = StateObject(wrappedValue: makeAccountLinkViewModel())
    }

    public var body: some View {
        Form {
            Section("Existing Account") {
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

            Section("Sign In With Another Device") {
                Text("Open Unhappy on your iPhone or another signed-in device and scan this QR to approve sign-in.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if accountLinkViewModel.isRestoringByQR {
                    ProgressView(
                        "Waiting for QR approval\(String(repeating: ".", count: accountLinkViewModel.qrRestoreProgressDots))"
                    )
                }

                if let qrCode = accountLinkViewModel.qrRestoreCode {
                    HStack {
                        Spacer()
                        QRCodeImageView(content: qrCode, size: 220)
                        Spacer()
                    }
                }
            }

            Section("Sign In With Secret Key") {
                SecureField("Account Secret (base64url)", text: $accountLinkViewModel.accountSecretBase64URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())

                if accountLinkViewModel.isRestoring {
                    ProgressView("Signing in from secret key...")
                }
            }

            Section("Actions") {
                Button("Start QR Sign-In") {
                    qrRestoreTask?.cancel()
                    qrRestoreTask = Task {
                        defer { qrRestoreTask = nil }
                        if let restoredToken = await accountLinkViewModel.restoreTokenFromQRCode(
                            serverURLString: viewModel.serverURLString
                        ) {
                            viewModel.apiToken = restoredToken
                            localStatusMessage = "Signed in from another device"
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

                Button("Sign In With Secret Key") {
                    Task {
                        if let restoredToken = await accountLinkViewModel.restoreToken(
                            serverURLString: viewModel.serverURLString
                        ) {
                            viewModel.apiToken = restoredToken
                            localStatusMessage = "Signed in from secret key"
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

                Button("Copy API Token") {
                    copyTokenToClipboard(viewModel.apiToken)
                    localStatusMessage = "Copied API token"
                }
                .disabled(!hasToken)

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
                if let localStatusMessage {
                    Text(localStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("Use Existing Account")
        .navigationBarTitleDisplayMode(.inline)
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
}

private func copyTokenToClipboard(_ value: String) {
#if canImport(UIKit)
    UIPasteboard.general.string = value
#endif
}
