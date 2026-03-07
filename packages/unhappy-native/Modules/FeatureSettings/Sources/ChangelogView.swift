import SwiftUI

public struct ChangelogView: View {
    private let entries: [ChangelogEntry]

    public init(entries: [ChangelogEntry] = SettingsChangelog.entries) {
        self.entries = entries
    }

    public var body: some View {
        List(entries) { entry in
            Section {
                ForEach(entry.highlights, id: \.self) { highlight in
                    Label {
                        Text(highlight)
                    } icon: {
                        Image(systemName: "sparkle")
                            .foregroundStyle(.secondary)
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
        .navigationTitle("Changelog")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ChangelogView()
    }
}
