import SwiftUI

struct MultiAgentStatusPresentation: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case inProgress
    }

    let summaryText: String
    let statusText: String
    let symbolName: String
    let state: State

    var badgeBackground: Color {
        Color.green.opacity(0.16)
    }

    var badgeForeground: Color {
        Color.green
    }
}

struct MultiAgentStatusBadge: View {
    let presentation: MultiAgentStatusPresentation

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: presentation.symbolName)
                .font(.caption2.weight(.semibold))
            Text(presentation.summaryText)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(presentation.badgeForeground)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(presentation.badgeBackground)
        )
        .overlay {
            Capsule(style: .continuous)
                .stroke(presentation.badgeForeground.opacity(0.22), lineWidth: 1)
        }
    }
}

enum MultiAgentStatusPresentationBuilder {
    static func make(inProgressCount: Int) -> MultiAgentStatusPresentation? {
        let safeCount = max(0, inProgressCount)
        guard safeCount > 0 else { return nil }

        let summaryText: String
        if safeCount == 1 {
            summaryText = "1 multi-agent task"
        } else {
            summaryText = "\(safeCount) multi-agent tasks"
        }

        return MultiAgentStatusPresentation(
            summaryText: summaryText,
            statusText: "진행중",
            symbolName: "bolt.fill",
            state: .inProgress
        )
    }
}
