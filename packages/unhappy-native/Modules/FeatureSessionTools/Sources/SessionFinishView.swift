import SwiftUI
import CoreKit

@MainActor
public struct SessionFinishView: View {
    let session: APISession
    let serverURLString: String
    let token: String

    @StateObject private var viewModel: SessionToolsViewModel
    @State private var baseRepoPath: String = ""
    @State private var worktreePath: String = ""
    @State private var worktreeBranch: String = ""
    @State private var mainBranch: String = "main"
    @State private var commitMessage: String = ""
    @State private var pushAfterMerge = false

    @State private var isExecuting = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var lastOutput: String = ""
    @State private var showDeleteConfirmation = false

    public init(
        session: APISession,
        serverURLString: String,
        token: String,
        makeViewModel: @escaping @MainActor () -> SessionToolsViewModel
    ) {
        self.session = session
        self.serverURLString = serverURLString
        self.token = token
        _viewModel = StateObject(wrappedValue: makeViewModel())
    }

    public var body: some View {
        List {
            Section("Repository Paths") {
                TextField("Base repo path", text: $baseRepoPath)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Worktree path", text: $worktreePath)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Branches") {
                TextField("Worktree branch", text: $worktreeBranch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Main branch", text: $mainBranch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Toggle("Push after merge", isOn: $pushAfterMerge)
            }

            Section("Status") {
                Button(isExecuting ? "Checking…" : "Check Worktree Status") {
                    Task { await checkWorktreeStatus() }
                }
                .disabled(isExecuting || normalizedOptional(worktreePath) == nil)
            }

            Section("Commit") {
                TextField("Commit message", text: $commitMessage, axis: .vertical)
                    .lineLimit(2...4)
                Button(isExecuting ? "Committing…" : "Commit All Changes") {
                    Task { await commitChanges() }
                }
                .disabled(
                    isExecuting ||
                    normalizedOptional(worktreePath) == nil ||
                    normalizedOptional(commitMessage) == nil
                )
            }

            Section("Merge") {
                Button(isExecuting ? "Merging…" : "Merge Branch Into Main") {
                    Task { await mergeBranch() }
                }
                .disabled(
                    isExecuting ||
                    normalizedOptional(baseRepoPath) == nil ||
                    normalizedOptional(worktreeBranch) == nil ||
                    normalizedOptional(mainBranch) == nil
                )
            }

            Section("Pull Request") {
                Button(isExecuting ? "Creating PR…" : "Create Pull Request") {
                    Task { await createPullRequest() }
                }
                .disabled(
                    isExecuting ||
                    normalizedOptional(baseRepoPath) == nil ||
                    normalizedOptional(worktreePath) == nil ||
                    normalizedOptional(worktreeBranch) == nil ||
                    normalizedOptional(mainBranch) == nil
                )
            }

            Section("Danger Zone") {
                Button("Delete Worktree", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .disabled(
                    isExecuting ||
                    normalizedOptional(baseRepoPath) == nil ||
                    normalizedOptional(worktreePath) == nil ||
                    normalizedOptional(worktreeBranch) == nil
                )
                Text("Deletes worktree folder and local/remote branch. Ensure no active process still uses this path.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let statusMessage {
                Section("Result") {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }
            if let errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            if !lastOutput.isEmpty {
                Section("Output") {
                    Text(lastOutput)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(nil)
                }
            }
        }
        .navigationTitle("Finish")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Delete Worktree?",
            isPresented: $showDeleteConfirmation,
            actions: {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task { await deleteWorktree() }
                }
            },
            message: {
                Text("This operation removes the worktree and deletes the branch.")
            }
        )
    }

    private func checkWorktreeStatus() async {
        guard let worktreePath = normalizedOptional(worktreePath) else { return }
        await runOperation {
            let command = SessionFinishCommandBuilder.statusCommand(worktreePath: worktreePath)
            let result = await execute(command: command, timeout: 15_000)
            guard result.success else { return false }
            if result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                statusMessage = "Working tree is clean"
            } else {
                statusMessage = "Uncommitted changes detected"
            }
            return true
        }
    }

    private func commitChanges() async {
        guard
            let worktreePath = normalizedOptional(worktreePath),
            let message = normalizedOptional(commitMessage)
        else { return }
        await runOperation {
            let staged = await execute(
                command: SessionFinishCommandBuilder.stageAllCommand(worktreePath: worktreePath),
                timeout: 20_000
            )
            guard staged.success else { return false }

            let committed = await execute(
                command: SessionFinishCommandBuilder.commitCommand(worktreePath: worktreePath, message: message),
                timeout: 20_000
            )
            guard committed.success else { return false }

            statusMessage = "Commit completed"
            return true
        }
    }

    private func mergeBranch() async {
        guard
            let basePath = normalizedOptional(baseRepoPath),
            let branch = normalizedOptional(worktreeBranch),
            let main = normalizedOptional(mainBranch)
        else { return }

        await runOperation {
            let steps = [
                SessionFinishCommandBuilder.fetchCommand(basePath: basePath),
                SessionFinishCommandBuilder.checkoutCommand(basePath: basePath, branch: main),
                SessionFinishCommandBuilder.pullFastForwardCommand(basePath: basePath),
                SessionFinishCommandBuilder.mergeCommand(basePath: basePath, branch: branch)
            ]
            for step in steps {
                let result = await execute(command: step, timeout: 30_000)
                guard result.success else { return false }
            }
            if pushAfterMerge {
                let pushed = await execute(
                    command: SessionFinishCommandBuilder.pushCommand(basePath: basePath),
                    timeout: 30_000
                )
                guard pushed.success else { return false }
            }

            statusMessage = pushAfterMerge ? "Merge and push completed" : "Merge completed"
            return true
        }
    }

    private func createPullRequest() async {
        guard
            let basePath = normalizedOptional(baseRepoPath),
            let worktreePath = normalizedOptional(worktreePath),
            let branch = normalizedOptional(worktreeBranch),
            let main = normalizedOptional(mainBranch)
        else { return }

        await runOperation {
            let pushed = await execute(
                command: SessionFinishCommandBuilder.pushBranchCommand(worktreePath: worktreePath, branch: branch),
                timeout: 30_000
            )
            guard pushed.success else { return false }

            let created = await execute(
                command: SessionFinishCommandBuilder.createPRCommand(
                    basePath: basePath,
                    mainBranch: main,
                    branch: branch
                ),
                timeout: 30_000
            )
            guard created.success else { return false }

            statusMessage = "Pull request command completed"
            return true
        }
    }

    private func deleteWorktree() async {
        guard
            let basePath = normalizedOptional(baseRepoPath),
            let worktreePath = normalizedOptional(worktreePath),
            let branch = normalizedOptional(worktreeBranch)
        else { return }

        await runOperation {
            let removed = await execute(
                command: SessionFinishCommandBuilder.deleteWorktreeCommand(
                    basePath: basePath,
                    worktreePath: worktreePath
                ),
                timeout: 30_000
            )
            guard removed.success else { return false }

            _ = await execute(
                command: SessionFinishCommandBuilder.deleteLocalBranchCommand(basePath: basePath, branch: branch),
                timeout: 15_000
            )
            _ = await execute(
                command: SessionFinishCommandBuilder.deleteRemoteBranchCommand(basePath: basePath, branch: branch),
                timeout: 20_000
            )

            statusMessage = "Worktree delete commands completed"
            return true
        }
    }

    private func runOperation(_ block: () async -> Bool) async {
        isExecuting = true
        statusMessage = nil
        errorMessage = nil
        defer { isExecuting = false }
        _ = await block()
    }

    private func execute(command: String, timeout: Int) async -> CommandExecutionResult {
        viewModel.bashCommand = command
        viewModel.bashWorkingDirectory = "/"
        viewModel.bashTimeoutMilliseconds = String(timeout)
        await viewModel.runBash(
            sessionID: session.id,
            serverURLString: serverURLString,
            token: token
        )

        let combined = [viewModel.bashStdout, viewModel.bashStderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        lastOutput = combined

        if let error = viewModel.bashErrorMessage, !error.isEmpty {
            errorMessage = error
            return CommandExecutionResult(success: false, stdout: viewModel.bashStdout)
        }
        return CommandExecutionResult(success: true, stdout: viewModel.bashStdout)
    }
}

private struct CommandExecutionResult {
    let success: Bool
    let stdout: String
}

private func normalizedOptional(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
