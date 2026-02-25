import Foundation

enum SessionFileDiffCommandBuilder {
    static func diffCommand(filePath: String, workingDirectory: String?) -> String {
        let normalizedPath = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedWorkingDirectory = normalizedOptional(workingDirectory)
        let targetDirectory = normalizedWorkingDirectory
            ?? parentDirectory(from: normalizedPath)
            ?? "."
        return "git -C \(bashQuote(targetDirectory)) diff --no-ext-diff -- \(bashQuote(normalizedPath))"
    }

    static func parentDirectory(from filePath: String) -> String? {
        let normalizedPath = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else { return nil }
        guard let slashIndex = normalizedPath.lastIndex(of: "/") else { return nil }
        if slashIndex == normalizedPath.startIndex {
            return "/"
        }
        return String(normalizedPath[..<slashIndex])
    }

    private static func bashQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
