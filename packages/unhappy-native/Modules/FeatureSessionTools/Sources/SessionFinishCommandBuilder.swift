import Foundation

enum SessionFinishCommandBuilder {
    static func currentDirectoryCommand() -> String {
        "pwd"
    }

    static func resolveMainBranchCommand(basePath: String) -> String {
        """
        if ref=$(git -C \(bashQuote(basePath)) symbolic-ref refs/remotes/origin/HEAD 2>/dev/null); then \
            echo "$ref"; \
        elif git -C \(bashQuote(basePath)) rev-parse --verify origin/main >/dev/null 2>&1; then \
            echo "refs/remotes/origin/main"; \
        elif git -C \(bashQuote(basePath)) rev-parse --verify origin/master >/dev/null 2>&1; then \
            echo "refs/remotes/origin/master"; \
        else \
            echo ""; \
        fi
        """
    }

    static func showCurrentBranchCommand(worktreePath: String) -> String {
        "if ref=$(git -C \(bashQuote(worktreePath)) branch --show-current 2>/dev/null); then echo \"$ref\"; else echo \"\"; fi"
    }

    static func parseMainBranch(from output: String) -> String? {
        let firstLine = output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        guard let firstLine, !firstLine.isEmpty else { return nil }
        if let range = firstLine.range(of: "refs/remotes/origin/") {
            let branch = String(firstLine[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return branch.isEmpty ? nil : branch
        }
        return firstLine
    }

    static func statusCommand(worktreePath: String) -> String {
        "git -C \(bashQuote(worktreePath)) status --porcelain"
    }

    static func stageAllCommand(worktreePath: String) -> String {
        "git -C \(bashQuote(worktreePath)) add -A"
    }

    static func commitCommand(worktreePath: String, message: String) -> String {
        "git -C \(bashQuote(worktreePath)) commit -m \(bashQuote(message))"
    }

    static func fetchCommand(basePath: String) -> String {
        "git -C \(bashQuote(basePath)) fetch origin"
    }

    static func checkoutCommand(basePath: String, branch: String) -> String {
        "git -C \(bashQuote(basePath)) checkout \(bashQuote(branch))"
    }

    static func pullFastForwardCommand(basePath: String) -> String {
        "git -C \(bashQuote(basePath)) pull --ff-only"
    }

    static func mergeCommand(basePath: String, branch: String) -> String {
        "git -C \(bashQuote(basePath)) merge \(bashQuote(branch)) --no-edit"
    }

    static func pushCommand(basePath: String) -> String {
        "git -C \(bashQuote(basePath)) push"
    }

    static func pushBranchCommand(worktreePath: String, branch: String) -> String {
        "git -C \(bashQuote(worktreePath)) push -u origin \(bashQuote(branch))"
    }

    static func createPRCommand(basePath: String, mainBranch: String, branch: String) -> String {
        "cd \(bashQuote(basePath)) && gh pr create --base \(bashQuote(mainBranch)) --head \(bashQuote(branch)) --fill"
    }

    static func deleteWorktreeCommand(basePath: String, worktreePath: String) -> String {
        "git -C \(bashQuote(basePath)) worktree remove \(bashQuote(worktreePath)) --force"
    }

    static func deleteLocalBranchCommand(basePath: String, branch: String) -> String {
        "git -C \(bashQuote(basePath)) branch -D \(bashQuote(branch))"
    }

    static func deleteRemoteBranchCommand(basePath: String, branch: String) -> String {
        "git -C \(bashQuote(basePath)) push origin --delete \(bashQuote(branch))"
    }

    private static func bashQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
