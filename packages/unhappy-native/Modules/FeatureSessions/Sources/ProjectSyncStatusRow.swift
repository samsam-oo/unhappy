import SwiftUI

struct ProjectSyncStatusPresentation: Equatable {
    enum Layout: Equatable {
        case leading
    }

    let layout: Layout
    let primaryText: String
    let secondaryText: String?
    let multiAgentStatus: MultiAgentStatusPresentation?

    init(
        multiAgentInProgressCount: Int,
        isRefreshing: Bool,
        refreshLabel: String
    ) {
        _ = isRefreshing
        _ = refreshLabel
        if let multiAgentStatus = MultiAgentStatusPresentationBuilder.make(
            inProgressCount: multiAgentInProgressCount
        ) {
            self.layout = .leading
            self.primaryText = multiAgentStatus.summaryText
            self.secondaryText = nil
            self.multiAgentStatus = multiAgentStatus
            return
        }
        self.layout = .leading
        self.primaryText = ""
        self.secondaryText = nil
        self.multiAgentStatus = nil
    }
}

public struct ProjectSyncStatusRow: View {
    let multiAgentInProgressCount: Int
    let isRefreshing: Bool
    let refreshLabel: String

    public init(
        multiAgentInProgressCount: Int = 0,
        isRefreshing: Bool,
        refreshLabel: String = "Refreshing projects…"
    ) {
        self.multiAgentInProgressCount = max(0, multiAgentInProgressCount)
        self.isRefreshing = isRefreshing
        self.refreshLabel = refreshLabel
    }

    public var body: some View {
        Group {
            if presentation.multiAgentStatus != nil {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: presentation.secondaryText == nil ? 0 : 2) {
                        HStack(spacing: 8) {
                            if let multiAgentStatus = presentation.multiAgentStatus {
                                Image(systemName: multiAgentStatus.symbolName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(multiAgentStatus.badgeForeground)
                                Text(multiAgentStatus.summaryText)
                                    .font(.subheadline.weight(.semibold))
                            } else {
                                Text(presentation.primaryText)
                                    .font(.subheadline.weight(.semibold))
                            }
                        }

                        if let secondaryText = presentation.secondaryText {
                            Text(secondaryText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var presentation: ProjectSyncStatusPresentation {
        ProjectSyncStatusPresentation(
            multiAgentInProgressCount: multiAgentInProgressCount,
            isRefreshing: isRefreshing,
            refreshLabel: refreshLabel
        )
    }
}
