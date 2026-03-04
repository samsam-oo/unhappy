import SwiftUI
import CoreKit

struct NewSessionCodexSessionsSheet: View {
    @ObservedObject var viewModel: NewSessionViewModel
    let serverURLString: String
    let token: String
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoadingCodexThreads && viewModel.codexThreads.isEmpty {
                    ProgressView("Loading Codex sessions…")
                } else if viewModel.codexThreads.isEmpty {
                    if let error = viewModel.codexThreadsErrorMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Unable to load Codex sessions")
                                .font(.headline)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Retry") {
                                Task {
                                    await viewModel.loadCodexThreads(
                                        serverURLString: serverURLString,
                                        token: token
                                    )
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    } else {
                        ContentUnavailableView(
                            "No existing Codex sessions",
                            systemImage: "list.bullet",
                            description: Text("Start one in CLI first, then refresh here.")
                        )
                    }
                } else {
                    ForEach(viewModel.codexThreads) { thread in
                        Button {
                            viewModel.selectCodexThread(thread)
                            onClose()
                            Task {
                                await viewModel.loadDirectory(
                                    serverURLString: serverURLString,
                                    token: token
                                )
                            }
                        } label: {
                            CodexThreadSelectionRow(thread: thread)
                        }
                        .buttonStyle(.plain)
                    }

                    if viewModel.isLoadingMoreCodexThreads {
                        HStack {
                            Spacer()
                            ProgressView("Loading more…")
                            Spacer()
                        }
                    } else if viewModel.codexThreadsHasNext {
                        Button("Load More") {
                            Task {
                                await viewModel.loadMoreCodexThreads(
                                    serverURLString: serverURLString,
                                    token: token
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }

                    if let error = viewModel.codexThreadsErrorMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Unable to load additional Codex sessions")
                                .font(.subheadline.weight(.semibold))
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Retry") {
                                Task {
                                    await viewModel.loadMoreCodexThreads(
                                        serverURLString: serverURLString,
                                        token: token
                                    )
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Codex Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onClose)
                }
            }
            .refreshable {
                await viewModel.loadCodexThreads(
                    serverURLString: serverURLString,
                    token: token
                )
            }
        }
    }
}

struct NewSessionClaudeSessionsSheet: View {
    @ObservedObject var viewModel: NewSessionViewModel
    let serverURLString: String
    let token: String
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoadingClaudeSessions && viewModel.claudeSessions.isEmpty {
                    ProgressView("Loading Claude sessions…")
                } else if viewModel.claudeSessions.isEmpty {
                    if let error = viewModel.claudeSessionsErrorMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Unable to load Claude sessions")
                                .font(.headline)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Retry") {
                                Task {
                                    await viewModel.loadClaudeSessions(
                                        serverURLString: serverURLString,
                                        token: token
                                    )
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    } else {
                        ContentUnavailableView(
                            "No existing Claude sessions",
                            systemImage: "list.bullet.rectangle",
                            description: Text("Start one in CLI first, then refresh here.")
                        )
                    }
                } else {
                    ForEach(viewModel.claudeSessions) { session in
                        Button {
                            viewModel.selectClaudeSession(session)
                            onClose()
                            Task {
                                await viewModel.loadDirectory(
                                    serverURLString: serverURLString,
                                    token: token
                                )
                            }
                        } label: {
                            ClaudeSessionSelectionRow(session: session)
                        }
                        .buttonStyle(.plain)
                    }

                    if viewModel.isLoadingMoreClaudeSessions {
                        HStack {
                            Spacer()
                            ProgressView("Loading more…")
                            Spacer()
                        }
                    } else if viewModel.claudeSessionsHasNext {
                        Button("Load More") {
                            Task {
                                await viewModel.loadMoreClaudeSessions(
                                    serverURLString: serverURLString,
                                    token: token
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }

                    if let error = viewModel.claudeSessionsErrorMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Unable to load additional Claude sessions")
                                .font(.subheadline.weight(.semibold))
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Retry") {
                                Task {
                                    await viewModel.loadMoreClaudeSessions(
                                        serverURLString: serverURLString,
                                        token: token
                                    )
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Claude Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onClose)
                }
            }
            .refreshable {
                await viewModel.loadClaudeSessions(
                    serverURLString: serverURLString,
                    token: token
                )
            }
        }
    }
}

private struct CodexThreadSelectionRow: View {
    let thread: APICodexThreadSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(thread.id)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let cwd = trimmedNonEmpty(thread.cwd) {
                Text(cwd)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        trimmedNonEmpty(thread.name) ?? "Untitled"
    }
}

private struct ClaudeSessionSelectionRow: View {
    let session: APIClaudeSessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.id)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if let cwd = trimmedNonEmpty(session.cwd) {
                Text(cwd)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let updatedAt = trimmedNonEmpty(session.updatedAt) {
                Text(updatedAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

private func trimmedNonEmpty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
