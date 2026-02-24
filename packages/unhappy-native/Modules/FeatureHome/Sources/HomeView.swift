import SwiftUI
import CoreKit

public struct HomeView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Unhappy Native")
                    .font(.largeTitle.bold())
                    .foregroundStyle(AppPalette.primaryText)

                Text("Tuist modular bootstrap is ready.")
                    .font(.body)
                    .foregroundStyle(AppPalette.secondaryText)

                HStack(spacing: 8) {
                    Circle()
                        .fill(AppPalette.accent)
                        .frame(width: 10, height: 10)
                    Text("Feature module is wired")
                        .font(.callout)
                        .foregroundStyle(AppPalette.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            .navigationTitle("Home")
        }
    }
}

#Preview {
    HomeView()
}
