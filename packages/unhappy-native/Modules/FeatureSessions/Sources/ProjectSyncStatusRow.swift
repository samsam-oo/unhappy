import SwiftUI

struct ProjectSyncStatusPresentation: Equatable {
    enum Layout: Equatable {
        case centered
        case leading
    }

    let layout: Layout
    let showsSpinner: Bool
    let primaryText: String
    let secondaryText: String?

    init(
        activeSessionsCount: Int,
        isRefreshing: Bool,
        refreshLabel: String
    ) {
        let normalizedActiveSessionsCount = max(0, activeSessionsCount)

        if normalizedActiveSessionsCount == 0 {
            self.layout = .centered
            self.showsSpinner = isRefreshing
            self.primaryText = isRefreshing ? refreshLabel : "Projects are up to date"
            self.secondaryText = nil
            return
        }

        self.layout = .leading
        self.showsSpinner = true
        if normalizedActiveSessionsCount == 1 {
            self.primaryText = "1 active session"
        } else {
            self.primaryText = "\(normalizedActiveSessionsCount) active sessions"
        }
        self.secondaryText = isRefreshing ? refreshLabel : nil
    }
}

public struct ProjectSyncStatusRow: View {
    let activeSessionsCount: Int
    let isRefreshing: Bool
    let refreshLabel: String

    public init(
        activeSessionsCount: Int,
        isRefreshing: Bool,
        refreshLabel: String = "Refreshing projects…"
    ) {
        self.activeSessionsCount = max(0, activeSessionsCount)
        self.isRefreshing = isRefreshing
        self.refreshLabel = refreshLabel
    }

    public var body: some View {
        Group {
            switch presentation.layout {
            case .centered:
                HStack(spacing: 10) {
                    if presentation.showsSpinner {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(presentation.primaryText)
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .center)

            case .leading:
                HStack(spacing: 10) {
                    if presentation.showsSpinner {
                        ProgressView()
                            .controlSize(.small)
                    }

                    VStack(alignment: .leading, spacing: presentation.secondaryText == nil ? 0 : 2) {
                        Text(presentation.primaryText)
                            .font(.subheadline.weight(.semibold))
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
            activeSessionsCount: activeSessionsCount,
            isRefreshing: isRefreshing,
            refreshLabel: refreshLabel
        )
    }
}
