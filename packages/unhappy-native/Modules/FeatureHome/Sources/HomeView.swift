import SwiftUI
import CoreKit
import FeatureInbox
import FeatureMachine
import FeatureNewSession
import FeatureSessions
import FeatureSessionTools
import FeatureSettings

@MainActor
public struct HomeView: View {
    private enum AuthenticatedTab: Hashable {
        case sessions
        case inbox
        case settings
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var settingsViewModel: SettingsViewModel
    @StateObject private var serverStatusViewModel: HomeServerConnectionStatusViewModel
    @State private var isCreatingAccount = false
    @State private var onboardingErrorMessage: String?
    @State private var onboardingStatusMessage: String?
    @State private var isRestoreNavigationPresented = false
    @State private var isServerSettingsPresented = false
    @State private var selectedAuthenticatedTab: AuthenticatedTab = .sessions
    private let onboarding: any HomeAccountOnboardingAction
    private let makeInboxViewModel: @MainActor () -> InboxViewModel
    private let makeSessionsViewModel: @MainActor () -> SessionsViewModel
    private let makeNewSessionViewModel: @MainActor () -> NewSessionViewModel
    private let makeSessionToolsViewModel: @MainActor () -> SessionToolsViewModel
    private let onSessionsChanged: @MainActor ([APISession]) async -> Void
    private let makeMachinesViewModel: @MainActor () -> MachinesViewModel
    private let makeUsageViewModel: @MainActor () -> UsageSettingsViewModel
    private let makeDaemonStatusViewModel: @MainActor () -> ConnectorsDaemonStatusViewModel
    private let makeTerminalConnectViewModel: @MainActor () -> TerminalConnectSettingsViewModel
    private let makeAccountLinkViewModel: @MainActor () -> AccountLinkSettingsViewModel

    public init(
        onboarding: any HomeAccountOnboardingAction,
        makeSettingsViewModel: @escaping @MainActor () -> SettingsViewModel,
        makeInboxViewModel: @escaping @MainActor () -> InboxViewModel,
        makeSessionsViewModel: @escaping @MainActor () -> SessionsViewModel,
        makeNewSessionViewModel: @escaping @MainActor () -> NewSessionViewModel,
        makeSessionToolsViewModel: @escaping @MainActor () -> SessionToolsViewModel,
        onSessionsChanged: @escaping @MainActor ([APISession]) async -> Void = { _ in },
        makeMachinesViewModel: @escaping @MainActor () -> MachinesViewModel,
        makeUsageViewModel: @escaping @MainActor () -> UsageSettingsViewModel,
        makeDaemonStatusViewModel: @escaping @MainActor () -> ConnectorsDaemonStatusViewModel,
        makeTerminalConnectViewModel: @escaping @MainActor () -> TerminalConnectSettingsViewModel,
        makeAccountLinkViewModel: @escaping @MainActor () -> AccountLinkSettingsViewModel,
        makeServerStatusViewModel: @escaping @MainActor () -> HomeServerConnectionStatusViewModel
    ) {
        self.onboarding = onboarding
        _settingsViewModel = StateObject(wrappedValue: makeSettingsViewModel())
        _serverStatusViewModel = StateObject(wrappedValue: makeServerStatusViewModel())
        self.makeInboxViewModel = makeInboxViewModel
        self.makeSessionsViewModel = makeSessionsViewModel
        self.makeNewSessionViewModel = makeNewSessionViewModel
        self.makeSessionToolsViewModel = makeSessionToolsViewModel
        self.onSessionsChanged = onSessionsChanged
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

    @ViewBuilder
    private var authenticatedHome: some View {
        if horizontalSizeClass == .regular {
            authenticatedRegularHome
        } else {
            authenticatedCompactHome
        }
    }

    private var authenticatedCompactHome: some View {
        TabView(selection: $selectedAuthenticatedTab) {
            InboxView(
                serverURLString: settingsViewModel.serverURLString,
                token: settingsViewModel.apiToken,
                makeViewModel: makeInboxViewModel
            )
            .tabItem {
                Label("Inbox", systemImage: "tray.full")
            }
            .tag(AuthenticatedTab.inbox)

            SessionsView(
                serverURLString: settingsViewModel.serverURLString,
                token: settingsViewModel.apiToken,
                hideInactiveSessions: settingsViewModel.hideInactiveSessions,
                defaultNewSessionAgent: settingsViewModel.defaultNewSessionAgent,
                onSessionsChanged: onSessionsChanged,
                makeViewModel: makeSessionsViewModel,
                makeNewSessionViewModel: makeNewSessionViewModel,
                makeSessionToolsViewModel: makeSessionToolsViewModel
            )
            .tabItem {
                Label("Sessions", systemImage: "bubble.left.and.bubble.right")
            }
            .tag(AuthenticatedTab.sessions)

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
            .tag(AuthenticatedTab.settings)
        }
    }

    private var authenticatedRegularHome: some View {
        HomeAuthenticatedRegularView(
            settingsViewModel: settingsViewModel,
            serverURLString: settingsViewModel.serverURLString,
            token: settingsViewModel.apiToken,
            hideInactiveSessions: settingsViewModel.hideInactiveSessions,
            defaultNewSessionAgent: settingsViewModel.defaultNewSessionAgent,
            makeInboxViewModel: makeInboxViewModel,
            makeSessionsViewModel: makeSessionsViewModel,
            makeNewSessionViewModel: makeNewSessionViewModel,
            makeSessionToolsViewModel: makeSessionToolsViewModel,
            onSessionsChanged: onSessionsChanged,
            makeMachinesViewModel: makeMachinesViewModel,
            makeUsageViewModel: makeUsageViewModel,
            makeDaemonStatusViewModel: makeDaemonStatusViewModel,
            makeTerminalConnectViewModel: makeTerminalConnectViewModel,
            makeAccountLinkViewModel: makeAccountLinkViewModel
        )
    }

    private var unauthenticatedHome: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    LinearGradient(
                        colors: onboardingBackgroundGradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    ScrollView {
                        if proxy.size.width > proxy.size.height {
                            landscapeOnboardingLayout
                                .padding(.horizontal, 36)
                                .padding(.vertical, 28)
                        } else {
                            portraitOnboardingLayout
                                .padding(.horizontal, 24)
                                .padding(.vertical, 32)
                        }
                    }
                    .frame(maxWidth: 960)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image(systemName: "bolt.shield.fill")
                        .foregroundStyle(.blue)
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Sessions")
                            .font(.headline)
                        if let subtitle = customServerSubtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            connectionStatusView
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isServerSettingsPresented = true
                    } label: {
                        Image(systemName: "server.rack")
                    }
                    .accessibilityLabel("Open Server Settings")
                }
            }
            .navigationDestination(isPresented: $isRestoreNavigationPresented) {
                AccountRestoreView(
                    viewModel: settingsViewModel,
                    makeAccountLinkViewModel: makeAccountLinkViewModel
                )
            }
            .navigationDestination(isPresented: $isServerSettingsPresented) {
                ServerSettingsView(viewModel: settingsViewModel)
            }
            .task(id: statusPollingTaskKey) {
                await pollServerStatus()
            }
        }
    }

    private var isPhoneLayout: Bool {
        horizontalSizeClass != .regular
    }

    private var portraitOnboardingLayout: some View {
        VStack(spacing: 24) {
            onboardingBranding
            featureBadgesRow
            serverInput
            onboardingActions
            onboardingFeedback
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    private var landscapeOnboardingLayout: some View {
        HStack(spacing: 24) {
            VStack(spacing: 18) {
                onboardingBranding
                featureBadgesRow
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 20) {
                serverInput
                onboardingActions
                onboardingFeedback
            }
            .frame(maxWidth: 360)
            .padding(20)
            .background(onboardingPanelBackground, in: RoundedRectangle(cornerRadius: 18))
        }
        .frame(maxWidth: .infinity)
    }

    private var onboardingBranding: some View {
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
    }

    private var featureBadgesRow: some View {
        HStack(spacing: 8) {
            featureBadge(title: "Encrypted", systemImage: "lock.fill")
            featureBadge(title: "Cross Platform", systemImage: "globe")
            featureBadge(title: "Fast Restore", systemImage: "bolt.fill")
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 6)
    }

    private var serverInput: some View {
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
    }

    @ViewBuilder
    private var onboardingActions: some View {
        VStack(spacing: 12) {
            onboardingActionCard(
                eyebrow: "Recommended",
                title: "Use Existing Account",
                description: "Sign in with your iPhone or another device by scanning a QR code or entering your account secret key.",
                buttonTitle: "Sign In From Existing Device",
                isPrimary: true,
                isDisabled: isCreatingAccount
            ) {
                onboardingErrorMessage = nil
                onboardingStatusMessage = nil
                isRestoreNavigationPresented = true
            }

            onboardingActionCard(
                eyebrow: nil,
                title: "Create New Account",
                description: "Generate a fresh account secret and API token for this device.",
                buttonTitle: isCreatingAccount ? "Creating Access Key..." : "Create New Account",
                isPrimary: false,
                isDisabled: isCreatingAccount,
                showsProgress: isCreatingAccount,
                action: createAccount
            )
        }
    }

    @ViewBuilder
    private var onboardingFeedback: some View {
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

    private func onboardingActionCard(
        eyebrow: String?,
        title: String,
        description: String,
        buttonTitle: String,
        isPrimary: Bool,
        isDisabled: Bool,
        showsProgress: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.headline)
            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Group {
                if isPrimary {
                    Button(action: action) {
                        HStack(spacing: 10) {
                            if showsProgress {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(buttonTitle)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDisabled)
                } else {
                    Button(action: action) {
                        HStack(spacing: 10) {
                            if showsProgress {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(buttonTitle)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isDisabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(onboardingCardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        .background(onboardingBadgeBackground, in: Capsule())
    }

    private var onboardingBackgroundGradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.08, green: 0.10, blue: 0.14),
                Color(red: 0.04, green: 0.05, blue: 0.08),
            ]
        }

        return [
            Color(red: 0.95, green: 0.97, blue: 1.0),
            Color(red: 0.98, green: 0.99, blue: 1.0),
        ]
    }

    private var onboardingPanelBackground: some ShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(Color.white.opacity(0.08))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }

    private var onboardingCardBackground: some ShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(Color.white.opacity(0.06))
        }
        return AnyShapeStyle(.regularMaterial)
    }

    private var onboardingBadgeBackground: some ShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(Color.white.opacity(0.08))
        }
        return AnyShapeStyle(.regularMaterial)
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

    private var customServerSubtitle: String? {
        let trimmed = settingsViewModel.serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host else {
            return nil
        }
        let isDefaultHost = host.caseInsensitiveCompare("api.unhappy.im") == .orderedSame
            && (url.port == nil || url.port == 443)
        guard !isDefaultHost else {
            return nil
        }
        if let port = url.port {
            return "\(host):\(port)"
        }
        return host
    }

    private var statusPollingTaskKey: String {
        settingsViewModel.serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        HStack(spacing: 4) {
            if connectionStatus == .connecting {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Circle()
                    .fill(connectionStatusColor)
                    .frame(width: 6, height: 6)
            }
            Text(connectionStatusText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(connectionStatusColor)
        }
        .accessibilityLabel("Server status \(connectionStatusText)")
    }

    private var connectionStatus: HomeServerConnectionStatus {
        if serverStatusViewModel.isLoading {
            return .connecting
        }
        return serverStatusViewModel.status
    }

    private var connectionStatusText: String {
        switch connectionStatus {
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .disconnected:
            return "Disconnected"
        }
    }

    private var connectionStatusColor: Color {
        switch connectionStatus {
        case .connecting:
            return .orange
        case .connected:
            return .green
        case .disconnected:
            return .secondary
        }
    }

    private func pollServerStatus() async {
        while !Task.isCancelled {
            await serverStatusViewModel.refresh(serverURLString: settingsViewModel.serverURLString)

            do {
                try await Task.sleep(for: .seconds(8))
            } catch {
                return
            }
        }
    }
}
