import SwiftUI
import CoreKit

struct SessionApprovalRequestRowModel: Identifiable, Equatable {
    let id: String
    let callID: String
    let toolName: String
    let summary: String?
}

struct SessionSummarySectionRows: View {
    let title: String
    let titleIsPrimary: Bool
    let sessionID: String
    let statusText: String
    let isActive: Bool
    let updatedText: String

    var body: some View {
        SessionListSectionBadgeRow(
            iconSystemName: "doc.text.magnifyingglass",
            title: "Session"
        )
        .sessionListRow(insets: SessionListRowInsets.badge)

        SessionSurfaceCard(cornerRadius: 10) {
            VStack(spacing: 0) {
                sessionSummaryPanelRow(
                    title: "Title",
                    value: title,
                    valueColor: titleIsPrimary ? AppPalette.primaryText : AppPalette.secondaryText
                )
                Divider().opacity(0.28)
                sessionSummaryPanelRow(
                    title: "ID",
                    value: sessionID,
                    valueFont: .footnote.monospaced(),
                    valueColor: AppPalette.secondaryText
                )
                Divider().opacity(0.28)
                sessionSummaryPanelRow(
                    title: "Status",
                    value: statusText,
                    valueColor: isActive ? AppPalette.liveActivity : AppPalette.secondaryText
                )
                Divider().opacity(0.28)
                sessionSummaryPanelRow(
                    title: "Updated",
                    value: updatedText,
                    valueColor: AppPalette.secondaryText
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .sessionListRow(insets: SessionListRowInsets.sectionCard)
    }

    private func sessionSummaryPanelRow(
        title: String,
        value: String,
        valueFont: Font = .subheadline.monospaced().weight(.semibold),
        valueColor: Color = AppPalette.primaryText
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(AppPalette.secondaryText)
            Spacer(minLength: 0)
            Text(value)
                .font(valueFont)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

struct SessionApprovalBottomSheet: View {
    let requests: [SessionApprovalRequestRowModel]
    let respondingRequestID: String?
    let isRecoveringDisconnectedSession: Bool
    let statusMessage: String?
    let errorMessage: String?
    let surfaceColor: Color
    let shadowColor: Color
    let onApprove: (String) -> Void
    let onDeny: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                Text("Approval Required")
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(AppPalette.secondaryText)
                    .textCase(.uppercase)
            }

            ForEach(requests) { request in
                approvalRequestRow(request)
                if request.id != requests.last?.id {
                    Divider().opacity(0.22)
                }
            }

            if let statusMessage, !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
            if isRecoveringDisconnectedSession {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Recovering disconnected session…")
                        .font(.footnote)
                        .foregroundStyle(AppPalette.secondaryText)
                }
            }
            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(surfaceColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.45), lineWidth: 1)
        )
        .shadow(
            color: shadowColor,
            radius: 8,
            y: 2
        )
    }

    @ViewBuilder
    private func approvalRequestRow(_ request: SessionApprovalRequestRowModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(request.toolName)
                    .font(.subheadline.monospaced().weight(.semibold))
                    .foregroundStyle(AppPalette.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Text(request.callID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(AppPalette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let summary = request.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption.monospaced())
                    .foregroundStyle(AppPalette.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            approvalRequestActionButtons(for: request)
        }
    }

    private func approvalRequestActionButtons(
        for request: SessionApprovalRequestRowModel
    ) -> some View {
        let isResponding = respondingRequestID == request.id
        let disableActions = respondingRequestID != nil || isRecoveringDisconnectedSession

        return HStack(spacing: 8) {
            Button {
                onApprove(request.id)
            } label: {
                if isResponding {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Approve")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(disableActions)

            Button(role: .destructive) {
                onDeny(request.id)
            } label: {
                Text("Deny")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .disabled(disableActions)
        }
    }
}

struct SessionSubAgentLiveBar: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.2.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppPalette.liveActivity)
            Text("\(count)개 진행중")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppPalette.liveActivity)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppPalette.liveActivityMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppPalette.liveActivity.opacity(0.4), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .shadow(color: AppPalette.liveActivity.opacity(0.2), radius: 6, y: 2)
    }
}
