import SwiftUI

public struct ChangelogView: View {
    private let entries: [ChangelogEntry]

    public init(entries: [ChangelogEntry] = SettingsChangelog.entries) {
        self.entries = entries
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                changelogHero

                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .font(.headline)
                            Text("\(entry.id) • \(entry.publishedAt)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(entry.highlights, id: \.self) { highlight in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(Color.primary.opacity(0.18))
                                    .frame(width: 7, height: 7)
                                    .padding(.top, 6)
                                Text(highlight)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                }
            }
        }
        .padding(20)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Changelog")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var changelogHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image("UnhappyMark")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("What changed in Unhappy")
                .font(.title3.weight(.bold))
            Text("Recent app updates, UI refinements, and session workflow fixes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

#Preview {
    NavigationStack {
        ChangelogView()
    }
}
