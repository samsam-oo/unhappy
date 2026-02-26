import SwiftUI

struct MultiAgentStatusPresentation: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case inProgress
        case completed
    }

    let summaryText: String
    let statusText: String
    let symbolName: String
    let state: State

    var badgeBackground: Color {
        switch state {
        case .inProgress:
            return Color.green.opacity(0.16)
        case .completed:
            return Color.gray.opacity(0.14)
        }
    }

    var badgeForeground: Color {
        switch state {
        case .inProgress:
            return Color.green
        case .completed:
            return Color.secondary
        }
    }
}

enum MultiAgentStatusPresentationBuilder {
    static func make(activeSessionsCount: Int, inProgress: Bool) -> MultiAgentStatusPresentation {
        let safeCount = max(0, activeSessionsCount)
        let summaryText: String
        if safeCount == 0 {
            summaryText = "No active sessions"
        } else if safeCount == 1 {
            summaryText = "1 active session"
        } else {
            summaryText = "\(safeCount) active sessions"
        }

        if inProgress {
            return MultiAgentStatusPresentation(
                summaryText: summaryText,
                statusText: "진행중",
                symbolName: "bolt.fill",
                state: .inProgress
            )
        }

        return MultiAgentStatusPresentation(
            summaryText: summaryText,
            statusText: "완료됨",
            symbolName: "checkmark.circle",
            state: .completed
        )
    }
}
