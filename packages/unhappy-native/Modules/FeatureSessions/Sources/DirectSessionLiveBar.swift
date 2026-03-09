import SwiftUI
import CoreKit

struct SessionSubAgentLiveBar: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.2.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppPalette.liveActivity)
            Text(count == 1 ? "1 multi-agent task" : "\(count) multi-agent tasks")
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
