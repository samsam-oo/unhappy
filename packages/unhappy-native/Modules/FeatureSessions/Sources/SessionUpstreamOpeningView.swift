import SwiftUI
import CoreKit

@MainActor
public struct SessionUpstreamOpeningView: View {
    let row: SessionLinkedUpstreamSession
    let serverURLString: String
    let token: String
    let makeDirectSessionViewModel: @MainActor (DirectSessionIdentity) -> DirectSessionViewModel

    public init(
        row: SessionLinkedUpstreamSession,
        serverURLString: String,
        token: String,
        makeDirectSessionViewModel: @escaping @MainActor (DirectSessionIdentity) -> DirectSessionViewModel
    ) {
        self.row = row
        self.serverURLString = serverURLString
        self.token = token
        self.makeDirectSessionViewModel = makeDirectSessionViewModel
    }

    public var body: some View {
        if let directIdentity {
            DirectSessionDetailView(
                serverURLString: serverURLString,
                token: token,
                makeViewModel: {
                    makeDirectSessionViewModel(directIdentity)
                }
            )
        } else {
            unavailableStateView
        }
    }

    private var unavailableStateView: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.orange)

            VStack(spacing: 6) {
                Text("Couldn't Open Session")
                    .font(.headline)
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(row.machineDisplayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let cwd = row.summary.cwd, !cwd.isEmpty {
                Text(cwd)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            Text("Direct \(row.summary.provider.displayName) session support is unavailable for this session.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Open Session")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var directIdentity: DirectSessionIdentity? {
        DirectSessionIdentityResolver.resolve(from: row)
    }
}
