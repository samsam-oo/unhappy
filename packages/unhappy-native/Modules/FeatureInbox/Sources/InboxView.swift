import SwiftUI

@MainActor
public struct InboxView: View {
    @StateObject private var viewModel: InboxViewModel
    private let serverURLString: String
    private let token: String

    public init(
        serverURLString: String,
        token: String,
        makeViewModel: @escaping @MainActor () -> InboxViewModel
    ) {
        self.serverURLString = serverURLString
        self.token = token
        _viewModel = StateObject(wrappedValue: makeViewModel())
    }

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading inbox…")
                } else if let errorMessage = viewModel.errorMessage {
                    ContentUnavailableView(
                        "Unable to load inbox",
                        systemImage: "tray.full",
                        description: Text(errorMessage)
                    )
                } else if viewModel.items.isEmpty {
                    ContentUnavailableView(
                        "No inbox items",
                        systemImage: "tray",
                        description: Text("Notifications and pending requests will appear here.")
                    )
                } else {
                    List(viewModel.items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.headline)
                            Text(item.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(item.timestamp, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Inbox")
            .task(id: "\(serverURLString)|\(token)") {
                viewModel.updateConfiguration(
                    serverURLString: serverURLString,
                    token: token
                )
                await viewModel.load()
            }
        }
    }
}

#Preview {
    InboxView(
        serverURLString: "https://api.unhappy.im",
        token: "preview-token"
    ) {
        InboxViewModel(loader: PreviewInboxLoader())
    }
}

private actor PreviewInboxLoader: InboxLoadingAction {
    func loadInboxItems(serverURLString: String, token: String) async throws -> [InboxItem] {
        [
            InboxItem(
                id: "1",
                title: "Daemon updated",
                subtitle: "Machine mac-mini-01 is now on the latest daemon build.",
                timestamp: Date().addingTimeInterval(-3600)
            )
        ]
    }
}
