import SwiftUI
import CoreKit

@MainActor
public struct SessionUpstreamLinkDetailView: View {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    let row: SessionLinkedUpstreamSession
    @ObservedObject var viewModel: SessionsViewModel
    let serverURLString: String
    let token: String
    let onLinkedSession: ((String) -> Void)?

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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                detailCard
                if let preview = row.summary.preview?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !preview.isEmpty {
                    previewCard(preview)
                }
                attachButton
                if let status = viewModel.upstreamSessionStatusMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !status.isEmpty {
                    statusCard(text: status)
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(row.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        SessionSurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text(row.summary.provider.displayName)
                        .modifier(DockChipModifier(tone: .primary))
                    Text(row.machineDisplayName)
                        .modifier(DockChipModifier(tone: .neutral))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(row.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppPalette.primaryText)
                    Text(row.summary.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(AppPalette.secondaryText)
                        .textSelection(.enabled)
                }

                Text("This is a live machine session. Attaching creates the app-side mirror you use for transcript, tools, and approvals.")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.secondaryText)
            }
            .padding(18)
        }
    }

    private var detailCard: some View {
        SessionSurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                detailRow("Working Directory", value: row.summary.cwd ?? "Unavailable")
                if let model = row.summary.model?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !model.isEmpty {
                    detailRow("Model", value: model)
                }
                if let effort = row.summary.effort?.rawValue.trimmingCharacters(in: .whitespacesAndNewlines),
                   !effort.isEmpty {
                    detailRow("Reasoning", value: effort.uppercased())
                }
                if let status = row.summary.statusType?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !status.isEmpty {
                    detailRow("Status", value: status)
                }
                if let updatedAt = localizedDateText(from: row.summary.updatedAt) {
                    detailRow("Updated", value: updatedAt)
                }
                if let createdAt = localizedDateText(from: row.summary.createdAt) {
                    detailRow("Created", value: createdAt)
                }
            }
            .padding(18)
        }
    }

    private func previewCard(_ preview: String) -> some View {
        SessionSurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Preview")
                    .font(.footnote.monospaced().weight(.semibold))
                    .foregroundStyle(AppPalette.secondaryText)
                Text(preview)
                    .font(.body)
                    .foregroundStyle(AppPalette.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
        }
    }

    private var attachButton: some View {
        Button {
            Task {
                let linkedSessionID = await viewModel.linkUpstreamSession(
                    row,
                    serverURLString: serverURLString,
                    token: token
                )
                if let linkedSessionID, !linkedSessionID.isEmpty {
                    onLinkedSession?(linkedSessionID)
                }
            }
        } label: {
            HStack(spacing: 10) {
                if viewModel.linkingUpstreamSessionID == row.id {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "link")
                }
                Text(viewModel.linkingUpstreamSessionID == row.id ? "Attaching…" : "Attach Session")
                    .font(.headline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.linkingUpstreamSessionID != nil)
    }

    private func statusCard(text: String) -> some View {
        SessionSurfaceCard(
            fillColor: Color.accentColor.opacity(0.08),
            strokeColor: Color.accentColor.opacity(0.18)
        ) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(AppPalette.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(AppPalette.secondaryText)
            Text(value)
                .font(.body)
                .foregroundStyle(AppPalette.primaryText)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func localizedDateText(from raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        guard let date = Self.formatter.date(from: raw) ?? Self.fallbackFormatter.date(from: raw) else {
            return raw
        }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }
}
