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
        guard row.summary.provider == .codex || row.summary.provider == .claude else { return nil }
        guard let cwd = row.summary.cwd?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cwd.isEmpty else {
            return nil
        }

        if row.summary.provider == .codex {
            guard let transcriptPath = row.summary.path?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !transcriptPath.isEmpty else {
                return nil
            }
            return DirectSessionIdentity(
                machineID: row.machineID,
                machineDisplayName: row.machineDisplayName,
                provider: .codex,
                upstreamSessionID: row.summary.id,
                title: row.title,
                cwd: cwd,
                transcriptPath: transcriptPath,
                model: row.summary.model
            )
        }

        return DirectSessionIdentity(
            machineID: row.machineID,
            machineDisplayName: row.machineDisplayName,
            provider: .claude,
            upstreamSessionID: row.summary.id,
            title: row.title,
            cwd: cwd,
            transcriptPath: nil,
            model: row.summary.model
        )
    }
}
