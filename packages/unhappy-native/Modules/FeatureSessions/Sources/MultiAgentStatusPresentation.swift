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
