import SwiftUI
import CoreKit
import FeatureMachine
import FeatureNewSession
import FeatureSessions
import FeatureSessionTools
import FeatureSettings

@MainActor
public struct HomeView: View {
    @StateObject private var settingsViewModel: SettingsViewModel
    @State private var isCreatingAccount = false
    @State private var onboardingErrorMessage: String?
    @State private var onboardingStatusMessage: String?
    @State private var isRestoreSheetPresented = false
    private let onboarding: any HomeAccountOnboardingAction
    private let makeSessionsViewModel: @MainActor () -> SessionsViewModel
    private let makeNewSessionViewModel: @MainActor () -> NewSessionViewModel
    private let makeSessionToolsViewModel: @MainActor () -> SessionToolsViewModel
    private let makeMachinesViewModel: @MainActor () -> MachinesViewModel
    private let makeUsageViewModel: @MainActor () -> UsageSettingsViewModel
    private let makeDaemonStatusViewModel: @MainActor () -> ConnectorsDaemonStatusViewModel
    private let makeTerminalConnectViewModel: @MainActor () -> TerminalConnectSettingsViewModel
    private let makeAccountLinkViewModel: @MainActor () -> AccountLinkSettingsViewModel

    public init(
        onboarding: any HomeAccountOnboardingAction,
        makeSettingsViewModel: @escaping @MainActor () -> SettingsViewModel,
        makeSessionsViewModel: @escaping @MainActor () -> SessionsViewModel,
        makeNewSessionViewModel: @escaping @MainActor () -> NewSessionViewModel,
        makeSessionToolsViewModel: @escaping @MainActor () -> SessionToolsViewModel,
        makeMachinesViewModel: @escaping @MainActor () -> MachinesViewModel,
        makeUsageViewModel: @escaping @MainActor () -> UsageSettingsViewModel,
        makeDaemonStatusViewModel: @escaping @MainActor () -> ConnectorsDaemonStatusViewModel,
        makeTerminalConnectViewModel: @escaping @MainActor () -> TerminalConnectSettingsViewModel,
        makeAccountLinkViewModel: @escaping @MainActor () -> AccountLinkSettingsViewModel
    ) {
        self.onboarding = onboarding
        _settingsViewModel = StateObject(wrappedValue: makeSettingsViewModel())
        self.makeSessionsViewModel = makeSessionsViewModel
        self.makeNewSessionViewModel = makeNewSessionViewModel
        self.makeSessionToolsViewModel = makeSessionToolsViewModel
        self.makeMachinesViewModel = makeMachinesViewModel
        self.makeUsageViewModel = makeUsageViewModel
        self.makeDaemonStatusViewModel = makeDaemonStatusViewModel
        self.makeTerminalConnectViewModel = makeTerminalConnectViewModel
        self.makeAccountLinkViewModel = makeAccountLinkViewModel
    }

    public var body: some View {
        Group {
            if hasToken {
                authenticatedHome
            } else {
                unauthenticatedHome
            }
        }
        .task {
            await settingsViewModel.loadFromStore()
        }
    }

    private var hasToken: Bool {
        !settingsViewModel.apiToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private var authenticatedHome: some View {
        TabView {
            SessionsView(
                serverURLString: settingsViewModel.serverURLString,
                token: settingsViewModel.apiToken,
                hideInactiveSessions: settingsViewModel.hideInactiveSessions,
                defaultNewSessionAgent: settingsViewModel.defaultNewSessionAgent,
                makeViewModel: makeSessionsViewModel,
                makeNewSessionViewModel: makeNewSessionViewModel,
                makeSessionToolsViewModel: makeSessionToolsViewModel
            )
                .tabItem {
                    Label("Sessions", systemImage: "bubble.left.and.bubble.right")
                }

            SettingsView(
                viewModel: settingsViewModel,
                makeMachinesViewModel: makeMachinesViewModel,
                makeUsageViewModel: makeUsageViewModel,
                makeDaemonStatusViewModel: makeDaemonStatusViewModel,
                makeTerminalConnectViewModel: makeTerminalConnectViewModel,
                makeAccountLinkViewModel: makeAccountLinkViewModel
            )
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }

    private var unauthenticatedHome: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.97, blue: 1.0),
                        Color(red: 0.98, green: 0.99, blue: 1.0),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 10) {
                            Image(systemName: "bolt.shield.fill")
                                .font(.system(size: 40, weight: .semibold))
                                .foregroundStyle(.blue)
                            Text("Unhappy Coder")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                            Text("Launch your first secure session in seconds.")
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            featureBadge(title: "Encrypted", systemImage: "lock.fill")
                            featureBadge(title: "Cross Platform", systemImage: "globe")
                            featureBadge(title: "Fast Restore", systemImage: "bolt.fill")
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 6)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Server")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            TextField("https://api.unhappy.im", text: $settingsViewModel.serverURLString)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .font(.body.monospaced())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }

                        VStack(spacing: 10) {
                            Button(action: createAccount) {
                                HStack(spacing: 10) {
                                    if isCreatingAccount {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                    Text(isCreatingAccount ? "Creating Account..." : "Create Account")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isCreatingAccount)

                            Button("Restore Existing Account") {
                                onboardingErrorMessage = nil
                                onboardingStatusMessage = nil
                                isRestoreSheetPresented = true
                            }
                            .buttonStyle(.bordered)
                            .disabled(isCreatingAccount)
                        }

                        if let onboardingStatusMessage {
                            Text(onboardingStatusMessage)
                                .font(.footnote)
                                .foregroundStyle(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let onboardingErrorMessage {
                            Text(onboardingErrorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 32)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isRestoreSheetPresented) {
                NavigationStack {
                    AccountRestoreView(
                        viewModel: settingsViewModel,
                        makeAccountLinkViewModel: makeAccountLinkViewModel
                    )
                }
            }
        }
    }

    private func featureBadge(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }

    private func createAccount() {
        onboardingErrorMessage = nil
        onboardingStatusMessage = nil
        let serverURLString = settingsViewModel.serverURLString
        isCreatingAccount = true

        Task {
            defer { isCreatingAccount = false }
            do {
                let token = try await onboarding.createAccount(serverURLString: serverURLString)
                settingsViewModel.apiToken = token
                onboardingStatusMessage = "Account created successfully"
            } catch {
                onboardingErrorMessage = onboardingErrorDescription(error)
            }
        }
    }

    private func onboardingErrorDescription(_ error: Error) -> String {
        if let onboardingError = error as? HomeAccountOnboardingError,
           let description = onboardingError.errorDescription {
            return description
        }
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

#Preview {
    HomeView(
        onboarding: PreviewHomeAccountOnboarding(),
        makeSettingsViewModel: {
            SettingsViewModel(
                settingsManager: SettingsUseCase(store: UserDefaultsAppSettingsStore())
            )
        },
        makeSessionsViewModel: { SessionsViewModel(service: URLSessionSessionsService()) },
        makeNewSessionViewModel: {
            let service = URLSessionMachinesService()
            return NewSessionViewModel(
                machinesLoader: NewSessionMachinesLoadUseCase(service: service),
                directoryLister: NewSessionDirectoryListUseCase(service: service),
                spawner: NewSessionSpawnUseCase(service: service),
                recentProjectsManager: NewSessionNoopRecentProjectsManager(),
                profilesManager: NewSessionNoopProfilesManager()
            )
        },
        makeSessionToolsViewModel: {
            let service = URLSessionSessionsService()
            let basher = SessionBashUseCase(service: service)
            return SessionToolsViewModel(
                fileLoader: SessionFileLoadUseCase(service: service),
                directoryLister: SessionDirectoryListUseCase(service: service),
                fileWriter: SessionFileWriteUseCase(service: service),
                fileDiffPreviewer: SessionFileDiffPreviewUseCase(basher: basher),
                killer: SessionKillUseCase(service: service),
                aborter: SessionTaskAbortUseCase(service: service),
                permissionResponder: SessionPermissionUseCase(service: service),
                modeSwitcher: SessionModeSwitchUseCase(service: service),
                basher: basher,
                ripgrepRunner: SessionRipgrepUseCase(service: service),
                difftasticRunner: SessionDifftasticUseCase(service: service)
            )
        },
        makeMachinesViewModel: {
            let service = URLSessionMachinesService()
            return MachinesViewModel(
                loader: MachinesLoadUseCase(service: service),
                spawner: MachineSpawnUseCase(service: service),
                updater: MachineDaemonUpdateUseCase(service: service),
                stopper: MachineDaemonStopUseCase(service: service)
            )
        },
        makeUsageViewModel: {
            UsageSettingsViewModel(
                usageLoader: SettingsUsageLoadUseCase(service: URLSessionSessionsService())
            )
        },
        makeDaemonStatusViewModel: {
            ConnectorsDaemonStatusViewModel(
                loader: DaemonStatusLoadUseCase(service: URLSessionMachinesService())
            )
        },
        makeTerminalConnectViewModel: {
            TerminalConnectSettingsViewModel(
                connector: TerminalConnectUseCase(
                    service: URLSessionTerminalAuthService(),
                    dataKeyStore: UserDefaultsTerminalDataKeyStore(),
                    encryptor: TweetNaclTerminalAuthEncryptor()
                )
            )
        },
        makeAccountLinkViewModel: {
            AccountLinkSettingsViewModel(
                linker: AccountLinkUseCase(
                    service: URLSessionAccountAuthService(),
                    encryptor: TweetNaclTerminalAuthEncryptor()
                ),
                restorer: AccountRestoreUseCase(
                    authTokenService: URLSessionAuthTokenService()
                ),
                qrRestorer: AccountRestoreQRUseCase(
                    requestService: URLSessionAccountRestoreRequestService()
                ),
                secretStore: UserDefaultsAccountSecretStore()
            )
        }
    )
}

private actor PreviewHomeAccountOnboarding: HomeAccountOnboardingAction {
    func createAccount(serverURLString: String) async throws -> String {
        "preview-token"
    }
}
