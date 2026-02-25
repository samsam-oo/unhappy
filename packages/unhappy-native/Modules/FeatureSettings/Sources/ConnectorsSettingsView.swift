import SwiftUI

@MainActor
struct ConnectorsSettingsView: View {
    private let serverURLString: String
    private let token: String
    @StateObject private var daemonStatusViewModel: ConnectorsDaemonStatusViewModel

    init(
        serverURLString: String,
        token: String,
        makeDaemonStatusViewModel: @escaping @MainActor () -> ConnectorsDaemonStatusViewModel
    ) {
        self.serverURLString = serverURLString
        self.token = token
        _daemonStatusViewModel = StateObject(wrappedValue: makeDaemonStatusViewModel())
    }

    var body: some View {
        Form {
            Section("Daemon") {
                LabeledContent("Status") {
                    Text(statusText)
                        .foregroundStyle(statusColor)
                }
                if daemonStatusViewModel.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Checking daemon status…")
                            .foregroundStyle(.secondary)
                    }
                }
                if let snapshot = daemonStatusViewModel.snapshot {
                    LabeledContent("Machines") {
                        Text("\(snapshot.totalMachines)")
                    }
                    LabeledContent("Online") {
                        Text("\(snapshot.onlineMachines)")
                    }
                }
                if let errorMessage = daemonStatusViewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Button("Refresh Status") {
                    Task {
                        await daemonStatusViewModel.load(serverURLString: serverURLString, token: token)
                    }
                }
            }

            Section("Providers") {
                Text("Codex, Claude, and Gemini authentication is managed by daemon profiles or environment variables.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("App") {
                LabeledContent("API Token") {
                    Text(hasToken ? "Configured" : "Missing")
                        .foregroundStyle(hasToken ? .green : .secondary)
                }
            }

            Section("Notes") {
                Text("Connection setup is considered complete when daemon status is Running (at least one machine online).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Connectors")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(serverURLString)|\(token)") {
            await daemonStatusViewModel.load(serverURLString: serverURLString, token: token)
        }
    }

    private var hasToken: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var statusText: String {
        switch statusState {
        case .checking:
            return "Checking"
        case .unavailable:
            return "Unavailable"
        case .missingToken:
            return "Missing API Token"
        case .running:
            return "Running"
        case .offline:
            return "Offline"
        case .none:
            return "No Machines"
        case .unknown:
            return "Unknown"
        }
    }

    private var statusColor: Color {
        switch statusState {
        case .running:
            return .green
        case .offline, .unavailable:
            return .orange
        case .missingToken:
            return .red
        default:
            return .secondary
        }
    }

    private var statusState: DaemonStatusState {
        if daemonStatusViewModel.isLoading {
            return .checking
        }
        if daemonStatusViewModel.errorMessage != nil {
            return .unavailable
        }
        guard let snapshot = daemonStatusViewModel.snapshot else {
            return hasToken ? .unknown : .missingToken
        }
        if snapshot.onlineMachines > 0 {
            return .running
        }
        if snapshot.totalMachines > 0 {
            return .offline
        }
        return .none
    }
}

private enum DaemonStatusState {
    case checking
    case unavailable
    case missingToken
    case running
    case offline
    case none
    case unknown
}
