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
    @State private var diffFiles: [SessionReviewDiffFilePresentation] = []
    @State private var selectedDiffFileID: String?

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
            Section("Auto Detect") {
                Button(isLoading ? "Detecting…" : "Use Current Session Path") {
                    Task { await detectCurrentRepositoryPath() }
                }
                .disabled(isLoading)
            }

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

            Section("Changed Files") {
                if isLoading {
                    ProgressView("Parsing diff files…")
                } else if diffFiles.isEmpty {
                    Text("No file summaries")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(diffFiles) { file in
                        Button {
                            selectedDiffFileID = file.id
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(file.path)
                                        .font(.footnote.monospaced())
                                        .lineLimit(1)
                                    Spacer()
                                    Text(file.hunkCount == 1 ? "1 hunk" : "\(file.hunkCount) hunks")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(file.preview)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Diff") {
                if isLoading {
                    ProgressView("Loading diff…")
                } else if diffOutput.isEmpty {
                    Text("No changes")
                        .foregroundStyle(.secondary)
                } else {
                    Text(selectedDiffFile?.patch ?? diffOutput)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(nil)
                }
            }

            if !diffOutput.isEmpty {
                Section("Raw Diff") {
                    Text(diffOutput)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(nil)
                }
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if normalizedOptional(repoPath) == nil {
                await detectCurrentRepositoryPath()
            }
        }
    }

    private func loadReviewDiff() async {
        isLoading = true
        statusMessage = nil
        errorMessage = nil
        diffOutput = ""
        diffFiles = []
        selectedDiffFileID = nil
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
            diffFiles = SessionReviewDiffPresentationBuilder.parseFiles(from: normalizedDiff)
            selectedDiffFileID = diffFiles.first?.id
            statusMessage = "Loaded diff (\(normalizedDiff.split(separator: "\n").count) lines)"
            diffOutput = normalizedDiff
        }
    }

    private func detectCurrentRepositoryPath() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let pwd = await runScript(
            SessionFinishCommandBuilder.currentDirectoryCommand(),
            timeout: 8_000,
            cwd: "/"
        )
        guard pwd.success else {
            errorMessage = pwd.errorMessage ?? "Failed to detect current directory"
            return
        }
        guard let currentPath = firstNonEmptyLine(pwd.stdout) else {
            errorMessage = "Current directory is unavailable"
            return
        }

        repoPath = currentPath
        statusMessage = "Detected repository path from session"
    }

    private func runScript(
        _ command: String,
        timeout: Int,
        cwd: String? = "/"
    ) async -> ScriptExecutionResult {
        viewModel.bashCommand = command
        viewModel.bashWorkingDirectory = cwd ?? ""
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

    private func firstNonEmptyLine(_ raw: String) -> String? {
        raw
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private var selectedDiffFile: SessionReviewDiffFilePresentation? {
        guard let selectedDiffFileID else { return nil }
        return diffFiles.first(where: { $0.id == selectedDiffFileID })
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
