import SwiftUI

public struct ChangelogView: View {
    private let entries: [ChangelogEntry]
    @Environment(\.colorScheme) private var colorScheme

    public init(entries: [ChangelogEntry] = SettingsChangelog.entries) {
        self.entries = entries
    }

    public var body: some View {
        List {
            Section {
                HStack(alignment: .center, spacing: 14) {
                    Image("UnhappyMark")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("What changed in Unhappy")
                            .font(.headline)
                        Text("Recent app updates, UI refinements, and session workflow fixes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listRowBackground(Color(uiColor: .secondarySystemBackground))

            ForEach(entries) { entry in
                Section {
                    ForEach(entry.highlights, id: \.self) { highlight in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(Color.primary.opacity(0.18))
                                .frame(width: 7, height: 7)
                                .padding(.top, 6)
                            Text(highlight)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                            .font(.headline)
                        Text("\(entry.id) • \(entry.publishedAt)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Changelog")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ChangelogView()
    }
}
