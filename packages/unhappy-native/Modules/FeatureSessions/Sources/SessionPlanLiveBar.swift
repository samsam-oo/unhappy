import SwiftUI
import SessionKit
import UIFoundation

struct SessionPlanLivePresentation: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case pending
        case inProgress
        case completed

        var label: String {
            switch self {
            case .pending:
                return "Planned"
            case .inProgress:
                return "In Progress"
            case .completed:
                return "Completed"
            }
        }
    }

    let title: String
    let subtitle: String?
    let status: Status
}

enum SessionPlanLivePresentationBuilder {
    static func latestPlan(
        in presentations: [SessionTranscriptMessagePresentation]
    ) -> SessionPlanLivePresentation? {
        let entries = presentations.flatMap(\.entries).reversed()
        for entry in entries {
            guard case .toolDetails(let tool)? = SessionTranscriptRichContentParser.richToolContent(for: entry),
                  tool.kind == .plan,
                  !tool.planItems.isEmpty else {
                continue
            }

            let status: SessionPlanLivePresentation.Status
            if tool.planItems.contains(where: { $0.status == .inProgress }) {
                status = .inProgress
            } else if tool.planItems.allSatisfy({ $0.status == .completed }) {
                status = .completed
            } else {
                status = .pending
            }

            let subtitle =
                tool.planItems.first(where: { $0.status == .inProgress })?.step ??
                tool.subtitle ??
                tool.planItems.first?.step

            return SessionPlanLivePresentation(
                title: "Plan · \(tool.planItems.count) \(tool.planItems.count == 1 ? "step" : "steps")",
                subtitle: subtitle,
                status: status
            )
        }
        return nil
    }
}

struct SessionPlanLiveBar: View {
    let presentation: SessionPlanLivePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusTint)
                Text(presentation.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusTint)
                Text(presentation.status.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusTint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(statusTint.opacity(0.12))
                    )
            }
            if let subtitle = presentation.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(AppPalette.primaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppPalette.liveActivityMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(statusTint.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .shadow(color: statusTint.opacity(0.18), radius: 6, y: 2)
    }

    private var statusTint: Color {
        switch presentation.status {
        case .pending:
            return AppPalette.secondaryText
        case .inProgress:
            return AppPalette.liveActivity
        case .completed:
            return .green
        }
    }
}
