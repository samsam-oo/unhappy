import Foundation
import CoreKit

@MainActor
protocol SessionUpstreamSessionAdapter {
    var provider: APIUpstreamSessionProvider { get }
    var title: String { get }
    var emptyStateTitle: String { get }
    var unavailableMessage: String { get }

    func isLoading(in viewModel: SessionsViewModel) -> Bool
    func errorMessage(in viewModel: SessionsViewModel) -> String?
    func summaries(in viewModel: SessionsViewModel) -> [APIUpstreamSessionSummary]
    func hasNext(in viewModel: SessionsViewModel) -> Bool
    func isResuming(summary: APIUpstreamSessionSummary, in viewModel: SessionsViewModel) -> Bool

    func load(
        in viewModel: SessionsViewModel,
        sessionID: String,
        serverURLString: String,
        token: String,
        cwd: String?
    ) async

    func loadMore(
        in viewModel: SessionsViewModel,
        sessionID: String,
        serverURLString: String,
        token: String,
        cwd: String?
    ) async

    func resume(
        in viewModel: SessionsViewModel,
        sourceSessionID: String,
        summary: APIUpstreamSessionSummary,
        serverURLString: String,
        token: String,
        directory: String
    ) async
}

@MainActor
struct SessionCodexUpstreamAdapter: SessionUpstreamSessionAdapter {
    let provider: APIUpstreamSessionProvider = .codex
    let title = "Codex Sessions"
    let emptyStateTitle = "No existing Codex sessions"
    let unavailableMessage = "Codex session listing is unavailable in this build"

    func isLoading(in viewModel: SessionsViewModel) -> Bool { viewModel.isLoadingCodexThreads }
    func errorMessage(in viewModel: SessionsViewModel) -> String? { viewModel.selectedCodexThreadsErrorMessage }
    func summaries(in viewModel: SessionsViewModel) -> [APIUpstreamSessionSummary] {
        viewModel.selectedCodexThreads.map(\.upstreamSummary)
    }
    func hasNext(in viewModel: SessionsViewModel) -> Bool { false }
    func isResuming(summary: APIUpstreamSessionSummary, in viewModel: SessionsViewModel) -> Bool {
        viewModel.codexResumeInProgressThreadID == summary.id
    }

    func load(
        in viewModel: SessionsViewModel,
        sessionID: String,
        serverURLString: String,
        token: String,
        cwd: String?
    ) async {
        await viewModel.loadCodexThreads(
            for: sessionID,
            serverURLString: serverURLString,
            token: token,
            cwd: cwd
        )
    }

    func loadMore(
        in viewModel: SessionsViewModel,
        sessionID: String,
        serverURLString: String,
        token: String,
        cwd: String?
    ) async {
        await viewModel.loadCodexThreads(
            for: sessionID,
            serverURLString: serverURLString,
            token: token,
            cwd: cwd
        )
    }

    func resume(
        in viewModel: SessionsViewModel,
        sourceSessionID: String,
        summary: APIUpstreamSessionSummary,
        serverURLString: String,
        token: String,
        directory: String
    ) async {
        await viewModel.resumeCodexThread(
            from: sourceSessionID,
            codexResumeThreadID: summary.id,
            serverURLString: serverURLString,
            token: token,
            directory: directory
        )
    }
}

@MainActor
struct SessionClaudeUpstreamAdapter: SessionUpstreamSessionAdapter {
    let provider: APIUpstreamSessionProvider = .claude
    let title = "Claude Sessions"
    let emptyStateTitle = "No existing Claude sessions"
    let unavailableMessage = "Claude session listing is unavailable in this build"

    func isLoading(in viewModel: SessionsViewModel) -> Bool { viewModel.isLoadingClaudeSessions }
    func errorMessage(in viewModel: SessionsViewModel) -> String? { viewModel.selectedClaudeSessionsErrorMessage }
    func summaries(in viewModel: SessionsViewModel) -> [APIUpstreamSessionSummary] {
        viewModel.selectedClaudeSessions.map(\.upstreamSummary)
    }
    func hasNext(in viewModel: SessionsViewModel) -> Bool { false }
    func isResuming(summary: APIUpstreamSessionSummary, in viewModel: SessionsViewModel) -> Bool {
        viewModel.claudeResumeInProgressSessionID == summary.id
    }

    func load(
        in viewModel: SessionsViewModel,
        sessionID: String,
        serverURLString: String,
        token: String,
        cwd: String?
    ) async {
        await viewModel.loadClaudeSessions(
            for: sessionID,
            serverURLString: serverURLString,
            token: token,
            cwd: cwd
        )
    }

    func loadMore(
        in viewModel: SessionsViewModel,
        sessionID: String,
        serverURLString: String,
        token: String,
        cwd: String?
    ) async {
        await viewModel.loadClaudeSessions(
            for: sessionID,
            serverURLString: serverURLString,
            token: token,
            cwd: cwd
        )
    }

    func resume(
        in viewModel: SessionsViewModel,
        sourceSessionID: String,
        summary: APIUpstreamSessionSummary,
        serverURLString: String,
        token: String,
        directory: String
    ) async {
        await viewModel.resumeClaudeSession(
            from: sourceSessionID,
            claudeResumeSessionID: summary.id,
            serverURLString: serverURLString,
            token: token,
            directory: directory
        )
    }
}

@MainActor
struct SessionGeminiUpstreamAdapter: SessionUpstreamSessionAdapter {
    let provider: APIUpstreamSessionProvider = .gemini
    let title = "Gemini Sessions"
    let emptyStateTitle = "No existing Gemini sessions"
    let unavailableMessage = "Gemini session linking is not available yet"

    func isLoading(in viewModel: SessionsViewModel) -> Bool { false }
    func errorMessage(in viewModel: SessionsViewModel) -> String? { unavailableMessage }
    func summaries(in viewModel: SessionsViewModel) -> [APIUpstreamSessionSummary] { [] }
    func hasNext(in viewModel: SessionsViewModel) -> Bool { false }
    func isResuming(summary: APIUpstreamSessionSummary, in viewModel: SessionsViewModel) -> Bool { false }

    func load(
        in viewModel: SessionsViewModel,
        sessionID: String,
        serverURLString: String,
        token: String,
        cwd: String?
    ) async {}

    func loadMore(
        in viewModel: SessionsViewModel,
        sessionID: String,
        serverURLString: String,
        token: String,
        cwd: String?
    ) async {}

    func resume(
        in viewModel: SessionsViewModel,
        sourceSessionID: String,
        summary: APIUpstreamSessionSummary,
        serverURLString: String,
        token: String,
        directory: String
    ) async {}
}
