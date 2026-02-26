import Foundation

struct SessionReviewDiffFilePresentation: Equatable, Identifiable, Sendable {
    let id: String
    let path: String
    let hunkCount: Int
    let preview: String
    let patch: String
}

enum SessionReviewDiffPresentationBuilder {
    static func parseFiles(from rawDiff: String) -> [SessionReviewDiffFilePresentation] {
        let trimmed = rawDiff.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let lines = trimmed.components(separatedBy: .newlines)
        let blockStarts = lines.enumerated().compactMap { index, line in
            line.hasPrefix("diff --git ") ? index : nil
        }
        guard !blockStarts.isEmpty else { return [] }

        var files: [SessionReviewDiffFilePresentation] = []
        for (index, start) in blockStarts.enumerated() {
            let end = (index + 1 < blockStarts.count) ? blockStarts[index + 1] : lines.count
            guard start < end else { continue }
            let block = Array(lines[start..<end])
            guard let header = block.first else { continue }

            let parsedPath = parsePath(fromHeader: header) ?? "file-\(index + 1)"
            let hunkCount = block.filter { $0.hasPrefix("@@") }.count
            let previewLines = block
                .filter { line in
                    (line.hasPrefix("+") || line.hasPrefix("-")) &&
                    !line.hasPrefix("+++") &&
                    !line.hasPrefix("---")
                }
                .prefix(3)
            let preview = previewLines.isEmpty ? "No line-level changes preview" : previewLines.joined(separator: "\n")
            let patch = block.joined(separator: "\n")

            files.append(
                SessionReviewDiffFilePresentation(
                    id: "\(index)-\(parsedPath)",
                    path: parsedPath,
                    hunkCount: hunkCount,
                    preview: preview,
                    patch: patch
                )
            )
        }

        return files
    }

    static func parsePath(fromHeader header: String) -> String? {
        let prefix = "diff --git a/"
        guard header.hasPrefix(prefix) else { return nil }
        let tail = String(header.dropFirst(prefix.count))
        guard let separator = tail.range(of: " b/") else { return nil }
        let left = String(tail[..<separator.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rightStart = separator.upperBound
        let right = String(tail[rightStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if left != "dev/null", !left.isEmpty {
            return left
        }
        return right.isEmpty ? nil : right
    }
}
