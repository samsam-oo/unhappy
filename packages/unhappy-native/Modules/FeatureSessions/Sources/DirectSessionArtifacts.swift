import Foundation
import SessionKit

enum DirectSessionArtifacts {
    static func richEntries(
        from presentations: [SessionTranscriptMessagePresentation]
    ) -> [SessionTranscriptEntry] {
        presentations
            .flatMap(\.entries)
            .filter { SessionTranscriptRichContentParser.richToolContent(for: $0) != nil }
    }

    static func richEntries(
        from presentations: [SessionTranscriptMessagePresentation],
        matchingFilePath path: String
    ) -> [SessionTranscriptEntry] {
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            return richEntries(from: presentations)
        }

        return richEntries(from: presentations).filter { entry in
            matches(entry: entry, filePath: normalizedPath)
        }
    }

    private static func matches(entry: SessionTranscriptEntry, filePath: String) -> Bool {
        guard let richContent = SessionTranscriptRichContentParser.richToolContent(for: entry) else {
            return rawBody(entry.body, references: filePath)
        }

        switch richContent {
        case .commandExecution:
            return rawBody(entry.body, references: filePath)
        case .fileChanges(let changes):
            return changes.contains { change in
                pathMatches(change.path, filePath) ||
                pathMatches(change.movePath, filePath) ||
                change.diffFiles.contains(where: { pathMatches($0.path, filePath) })
            } || rawBody(entry.body, references: filePath)
        case .diff(let files):
            return files.contains(where: { pathMatches($0.path, filePath) }) ||
                rawBody(entry.body, references: filePath)
        case .toolDetails:
            return rawBody(entry.body, references: filePath)
        }
    }

    private static func pathMatches(_ candidate: String?, _ target: String) -> Bool {
        guard let candidate else { return false }

        let normalizedCandidate = NSString(string: candidate).standardizingPath
        let normalizedTarget = NSString(string: target).standardizingPath
        if normalizedCandidate == normalizedTarget {
            return true
        }

        let targetSuffix = "/" + normalizedTarget
        let candidateSuffix = "/" + normalizedCandidate
        return normalizedCandidate.hasSuffix(targetSuffix) ||
            normalizedTarget.hasSuffix(candidateSuffix)
    }

    private static func rawBody(_ body: String, references filePath: String) -> Bool {
        let normalizedPath = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else { return false }

        return body.contains(normalizedPath) ||
            body.contains(NSString(string: normalizedPath).lastPathComponent)
    }
}
