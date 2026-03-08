import SwiftUI

struct ProjectSyncStatusPresentation: Equatable {
    let showsSpinner: Bool
    let primaryText: String

    init(
        isRefreshing: Bool,
        refreshLabel: String
    ) {
        self.showsSpinner = isRefreshing
        self.primaryText = isRefreshing ? refreshLabel : "Projects are up to date"
    }
}

public struct ProjectSyncStatusRow: View {
    let isRefreshing: Bool
    let refreshLabel: String

    public init(
        isRefreshing: Bool,
        refreshLabel: String = "Refreshing projects…"
    ) {
        self.isRefreshing = isRefreshing
        self.refreshLabel = refreshLabel
    }

    public var body: some View {
        HStack(spacing: 10) {
            if presentation.showsSpinner {
                ProgressView()
                    .controlSize(.small)
            }
            Text(presentation.primaryText)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var presentation: ProjectSyncStatusPresentation {
        ProjectSyncStatusPresentation(
            isRefreshing: isRefreshing,
            refreshLabel: refreshLabel
        )
    }
}
