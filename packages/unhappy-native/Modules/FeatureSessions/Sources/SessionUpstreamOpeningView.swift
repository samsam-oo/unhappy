import SwiftUI
import CoreKit

@MainActor
public struct SessionUpstreamOpeningView: View {
    let row: SessionLinkedUpstreamSession
    @ObservedObject var viewModel: SessionsViewModel
    let serverURLString: String
    let token: String
    let onLinkedSession: ((String) -> Void)?

    @State private var didStartOpen = false

    public init(
        row: SessionLinkedUpstreamSession,
        viewModel: SessionsViewModel,
        serverURLString: String,
        token: String,
        onLinkedSession: ((String) -> Void)? = nil
    ) {
        self.row = row
        self.viewModel = viewModel
        self.serverURLString = serverURLString
        self.token = token
        self.onLinkedSession = onLinkedSession
    }

    public var body: some View {
        VStack(spacing: 18) {
            Image(systemName: currentStatusIcon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(currentStatusTint)

            VStack(spacing: 6) {
                Text(currentStatusTitle)
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

            if isOpening {
                ProgressView()
                    .controlSize(.regular)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(isOpening ? Color.secondary : Color.red)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Open Session")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: row.id) {
            guard !didStartOpen else { return }
            didStartOpen = true
            let linkedSessionID = await viewModel.linkUpstreamSession(
                row,
                serverURLString: serverURLString,
                token: token
            )
            if let linkedSessionID, !linkedSessionID.isEmpty {
                onLinkedSession?(linkedSessionID)
            }
        }
    }

    private var isOpening: Bool {
        viewModel.linkingUpstreamSessionID == row.id || !didStartOpen
    }

    private var statusMessage: String? {
        let normalized = viewModel.upstreamSessionStatusMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else { return nil }
        return normalized
    }

    private var currentStatusTitle: String {
        if isOpening {
            return "Opening Session…"
        }
        return statusMessage == nil ? "Session Opened" : "Couldn't Open Session"
    }

    private var currentStatusIcon: String {
        if isOpening {
            return "arrow.triangle.2.circlepath"
        }
        return statusMessage == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var currentStatusTint: Color {
        if isOpening {
            return .accentColor
        }
        return statusMessage == nil ? .green : .orange
    }
}
