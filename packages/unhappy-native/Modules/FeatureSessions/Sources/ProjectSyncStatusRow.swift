import SwiftUI

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
        HStack(spacing: 10) {
            if showsSpinner {
                ProgressView()
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: secondaryText == nil ? 0 : 2) {
                Text(primaryText)
                    .font(.subheadline.weight(.semibold))
                if let secondaryText {
                    Text(secondaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var showsSpinner: Bool {
        isRefreshing || activeSessionsCount > 0
    }

    private var primaryText: String {
        if activeSessionsCount == 0 {
            return refreshLabel
        }
        if activeSessionsCount == 1 {
            return "1 active session"
        }
        return "\(activeSessionsCount) active sessions"
    }

    private var secondaryText: String? {
        guard activeSessionsCount > 0 else { return nil }
        return isRefreshing ? refreshLabel : nil
    }
}
