import Foundation

enum SessionReviewCommandBuilder {
    static let repoOKSentinel = "__REPO_OK__"
    static let noRepoSentinel = "__NO_REPO__"
    static let hasHeadSentinel = "__HAS_HEAD__"
    static let noHeadSentinel = "__NO_HEAD__"

    static func verifyRepositoryScript(repoPath: String?) -> String {
        let target = repoTarget(repoPath)
        return "git -C \(bashQuote(target)) rev-parse --is-inside-work-tree >/dev/null 2>&1 && echo \(repoOKSentinel) || echo \(noRepoSentinel)"
    }

    static func verifyHeadScript(repoPath: String?) -> String {
        let target = repoTarget(repoPath)
        return "git -C \(bashQuote(target)) rev-parse --verify HEAD >/dev/null 2>&1 && echo \(hasHeadSentinel) || echo \(noHeadSentinel)"
    }

    static func diffCommand(repoPath: String?, hasHead: Bool) -> String {
        let target = repoTarget(repoPath)
        if hasHead {
            return "git -C \(bashQuote(target)) diff --no-ext-diff HEAD"
        }
        return "git -C \(bashQuote(target)) diff --no-ext-diff --cached"
    }

    private static func repoTarget(_ repoPath: String?) -> String {
        let trimmed = repoPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "." : trimmed
    }

    private static func bashQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
