import Foundation

enum SessionFinishCommandBuilder {
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
