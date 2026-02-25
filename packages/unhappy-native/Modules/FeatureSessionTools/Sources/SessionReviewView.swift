import SwiftUI
import CoreKit

@MainActor
public struct SessionReviewView: View {
    let session: APISession
    let serverURLString: String
    let token: String

    @StateObject private var viewModel: SessionToolsViewModel
    @State private var repoPath: String = ""
    @State private var isLoading = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var diffOutput: String = ""

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
            Section("Repository") {
                TextField("Repository path (optional)", text: $repoPath)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("If empty, current session directory is used.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(isLoading ? "Loading…" : "Load Review Diff") {
                    Task { await loadReviewDiff() }
                }
                .disabled(isLoading)
            }

            if let statusMessage {
                Section("Status") {
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

            Section("Diff") {
                if isLoading {
                    ProgressView("Loading diff…")
                } else if diffOutput.isEmpty {
                    Text("No changes")
                        .foregroundStyle(.secondary)
                } else {
                    Text(diffOutput)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(nil)
                }
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func loadReviewDiff() async {
        isLoading = true
        statusMessage = nil
        errorMessage = nil
        diffOutput = ""
        defer { isLoading = false }

        let normalizedRepoPath = normalizedOptional(repoPath)

        let repositoryCheck = await runScript(
            SessionReviewCommandBuilder.verifyRepositoryScript(repoPath: normalizedRepoPath),
            timeout: 8_000
        )
        guard repositoryCheck.success else {
            errorMessage = repositoryCheck.errorMessage ?? "Failed to verify repository"
            return
        }
        guard repositoryCheck.stdout.contains(SessionReviewCommandBuilder.repoOKSentinel) else {
            errorMessage = "Not a git repository"
            return
        }

        let headCheck = await runScript(
            SessionReviewCommandBuilder.verifyHeadScript(repoPath: normalizedRepoPath),
            timeout: 8_000
        )
        guard headCheck.success else {
            errorMessage = headCheck.errorMessage ?? "Failed to verify repository HEAD"
            return
        }
        let hasHead = headCheck.stdout.contains(SessionReviewCommandBuilder.hasHeadSentinel)
        let diffCommand = SessionReviewCommandBuilder.diffCommand(
            repoPath: normalizedRepoPath,
            hasHead: hasHead
        )

        let diff = await runScript(diffCommand, timeout: 20_000)
        guard diff.success else {
            errorMessage = diff.errorMessage ?? "Failed to load diff"
            return
        }

        let normalizedDiff = diff.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedDiff.isEmpty {
            statusMessage = "No changes"
            diffOutput = ""
        } else {
            statusMessage = "Loaded diff (\(normalizedDiff.split(separator: "\n").count) lines)"
            diffOutput = normalizedDiff
        }
    }

    private func runScript(_ command: String, timeout: Int) async -> ScriptExecutionResult {
        viewModel.bashCommand = command
        viewModel.bashWorkingDirectory = "/"
        viewModel.bashTimeoutMilliseconds = String(timeout)
        await viewModel.runBash(
            sessionID: session.id,
            serverURLString: serverURLString,
            token: token
        )
        if let error = viewModel.bashErrorMessage, !error.isEmpty {
            return ScriptExecutionResult(
                success: false,
                stdout: viewModel.bashStdout,
                errorMessage: error
            )
        }
        return ScriptExecutionResult(
            success: true,
            stdout: viewModel.bashStdout,
            errorMessage: nil
        )
    }
}

private func normalizedOptional(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private struct ScriptExecutionResult {
    let success: Bool
    let stdout: String
    let errorMessage: String?
}
