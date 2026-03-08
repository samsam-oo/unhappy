import SwiftUI
import CoreKit
import FeatureSessionTools

@MainActor
public struct SessionUpstreamOpeningView: View {
    let row: SessionLinkedUpstreamSession
    @ObservedObject var viewModel: SessionsViewModel
    let serverURLString: String
    let token: String
    let makeSessionToolsViewModel: @MainActor () -> SessionToolsViewModel
    let makeCodexDirectSessionViewModel: @MainActor (CodexDirectSessionIdentity) -> CodexDirectSessionViewModel

    @State private var didStartOpen = false
    @State private var linkedSessionID: String?

    public init(
        row: SessionLinkedUpstreamSession,
        viewModel: SessionsViewModel,
        serverURLString: String,
        token: String,
        makeSessionToolsViewModel: @escaping @MainActor () -> SessionToolsViewModel,
        makeCodexDirectSessionViewModel: @escaping @MainActor (CodexDirectSessionIdentity) -> CodexDirectSessionViewModel
    ) {
        self.row = row
        self.viewModel = viewModel
        self.serverURLString = serverURLString
        self.token = token
        self.makeSessionToolsViewModel = makeSessionToolsViewModel
        self.makeCodexDirectSessionViewModel = makeCodexDirectSessionViewModel
    }

    public var body: some View {
        if let codexIdentity {
            CodexDirectSessionDetailView(
                serverURLString: serverURLString,
                token: token,
                makeViewModel: {
                    makeCodexDirectSessionViewModel(codexIdentity)
                }
            )
        } else if let linkedSession {
            SessionDetailView(
                session: linkedSession,
                viewModel: viewModel,
                serverURLString: serverURLString,
                token: token,
                makeSessionToolsViewModel: makeSessionToolsViewModel
            )
        } else {
            openingStateView
        }
    }

    private var openingStateView: some View {
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
                self.linkedSessionID = linkedSessionID
            }
        }
    }

    private var linkedSession: APISession? {
        guard let linkedSessionID else { return nil }
        return viewModel.sessions.first(where: { $0.id == linkedSessionID })
    }

    private var codexIdentity: CodexDirectSessionIdentity? {
        guard row.summary.provider == .codex else { return nil }
        guard let cwd = row.summary.cwd?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cwd.isEmpty else {
            return nil
        }
        guard let transcriptPath = row.summary.path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !transcriptPath.isEmpty else {
            return nil
        }
        return CodexDirectSessionIdentity(
            machineID: row.machineID,
            machineDisplayName: row.machineDisplayName,
            threadID: row.summary.id,
            title: row.title,
            cwd: cwd,
            transcriptPath: transcriptPath,
            model: row.summary.model
        )
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
        return statusMessage == nil ? "Session Ready" : "Couldn't Open Session"
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
