import SwiftUI

public struct AboutView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                summaryCard
                versionCard
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image("UnhappyMark")
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            Text("Unhappy")
                .font(.largeTitle.weight(.bold))
            Text("A focused client for projects, sessions, approvals, and machine sync.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Why Unhappy")
                .font(.headline)
            Text("Unhappy keeps direct coding sessions visible, restores context cleanly, and makes approvals and machine state easier to track.")
                .foregroundStyle(.secondary)
            Text("The app is built to keep session control readable instead of burying important state in hidden transcript details.")
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private var versionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Build")
                .font(.headline)
            LabeledContent("Version") {
                Text(appVersion)
                    .font(.body.monospaced())
            }
            LabeledContent("Build") {
                Text(buildNumber)
                    .font(.body.monospaced())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
