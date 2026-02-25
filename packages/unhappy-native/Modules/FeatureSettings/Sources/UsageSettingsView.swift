import SwiftUI

@MainActor
struct UsageSettingsView: View {
    let serverURLString: String
    let token: String

    @StateObject private var viewModel: UsageSettingsViewModel

    init(
        serverURLString: String,
        token: String,
        makeViewModel: @escaping @MainActor () -> UsageSettingsViewModel
    ) {
        self.serverURLString = serverURLString
        self.token = token
        _viewModel = StateObject(wrappedValue: makeViewModel())
    }

    var body: some View {
        Form {
            Section("Usage") {
                if viewModel.isLoading {
                    ProgressView("Loading usage…")
                } else if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else if let snapshot = viewModel.snapshot {
                    LabeledContent("Total Sessions") {
                        Text("\(snapshot.totalSessions)")
                            .font(.footnote.monospaced())
                    }
                    LabeledContent("Active Sessions") {
                        Text("\(snapshot.activeSessions)")
                            .font(.footnote.monospaced())
                    }
                    LabeledContent("Inactive Sessions") {
                        Text("\(snapshot.inactiveSessions)")
                            .font(.footnote.monospaced())
                    }
                    LabeledContent("Last Activity") {
                        if let updatedAt = snapshot.lastUpdatedAt {
                            Text(Date(timeIntervalSince1970: updatedAt), style: .relative)
                        } else {
                            Text("No sessions")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No usage data")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Actions") {
                Button(viewModel.isLoading ? "Refreshing…" : "Refresh Usage") {
                    Task {
                        await viewModel.loadUsage(
                            serverURLString: serverURLString,
                            token: token
                        )
                    }
                }
                .disabled(viewModel.isLoading)
            }
        }
        .navigationTitle("Usage")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(serverURLString)|\(token)") {
            await viewModel.loadUsage(
                serverURLString: serverURLString,
                token: token
            )
        }
    }
}
