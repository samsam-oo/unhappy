import Foundation

enum DirectSessionArtifacts {
    static func richEntries(
        from presentations: [SessionTranscriptMessagePresentation]
    ) -> [SessionTranscriptEntry] {
        presentations
            .flatMap(\.entries)
            .filter { SessionTranscriptRichContentParser.richToolContent(for: $0) != nil }
    }
}
