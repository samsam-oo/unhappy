import Foundation
import Combine
@testable import FeatureSessions
import CoreKit

enum MockSessionsLoaderError: Error, Sendable {
    case failed
}

struct MockSessionsLoader: SessionsLoading {
    let result: Result<[APISession], MockSessionsLoaderError>

    func loadSessions(serverURLString: String, token: String) async throws -> [APISession] {
        switch result {
        case .success(let sessions):
            return sessions
        case .failure(let error):
            throw error
        }
    }
}

struct MockSessionsServiceForValidation: SessionsFetching, SessionsPagingFetching, SessionMessagesFetching, SessionDeleting, SessionTitleUpdating, SessionCodexThreadsFetching, SessionClaudeSessionsFetching, SessionSpawning {
    func fetchSessions(serverURL: URL, token: String) async throws -> [APISession] {
        []
    }

    func fetchSessionsPage(serverURL: URL, token: String, cursor: String?, limit: Int) async throws -> APISessionsPage {
        APISessionsPage(sessions: [], nextCursor: nil, hasNext: false)
    }

    func fetchSessionMessages(serverURL: URL, token: String, sessionID: String) async throws -> [APISessionMessage] {
        []
    }

    func deleteSession(serverURL: URL, token: String, sessionID: String) async throws {}

    func setSessionTitle(serverURL: URL, token: String, sessionID: String, title: String?) async throws {}

    func fetchCodexThreads(serverURL: URL, token: String, sessionID: String, limit: Int, cwd: String?) async throws -> [APICodexThreadSummary] {
        []
    }

    func fetchClaudeSessions(serverURL: URL, token: String, sessionID: String, limit: Int, cwd: String?) async throws -> [APIClaudeSessionSummary] {
        []
    }

    func spawnSession(
        serverURL: URL,
        token: String,
        sessionID: String,
        directory: String,
        agent: APISessionSpawnAgent?,
        codexResumeThreadID: String?,
        claudeResumeSessionID: String?,
        approvedNewDirectoryCreation: Bool?
    ) async throws -> APISessionSpawnResult {
        APISessionSpawnResult(
            success: true,
            sessionID: "session-new",
            requiresUserApproval: nil,
            actionRequired: nil,
            directory: nil,
            error: nil
        )
    }
}

struct MockSessionsPoller: SessionsPolling {
    let rows: [APISession]

    func makePollingStream(
        serverURLString: String,
        token: String,
        interval: Duration
    ) async -> AsyncThrowingStream<[APISession], Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(rows)
            continuation.finish()
        }
    }
}

enum MockSessionsPageLoaderError: Error, Sendable {
    case failed
}

struct MockSessionsPageLoader: SessionsPageLoading {
    let result: Result<SessionsPageResult, MockSessionsPageLoaderError>

    func loadPage(serverURLString: String, token: String, cursor: String?, limit: Int) async throws -> SessionsPageResult {
        switch result {
        case .success(let page):
            return page
        case .failure(let error):
            throw error
        }
    }
}

actor SequenceSessionsPageLoader: SessionsPageLoading {
    var pages: [SessionsPageResult]

    init(results: [SessionsPageResult]) {
        self.pages = results
    }

    func loadPage(serverURLString: String, token: String, cursor: String?, limit: Int) async throws -> SessionsPageResult {
        if pages.isEmpty {
            return SessionsPageResult(sessions: [], nextCursor: nil, hasNext: false)
        }
        return pages.removeFirst()
    }
}

enum MockSessionsMessagesLoaderError: Error, Sendable {
    case failed
}

struct MockSessionsMessagesLoader: SessionsMessagesLoading {
    let result: Result<[APISessionMessage], MockSessionsMessagesLoaderError>

    func loadMessages(serverURLString: String, token: String, sessionID: String) async throws -> [APISessionMessage] {
        switch result {
        case .success(let messages):
            return messages
        case .failure(let error):
            throw error
        }
    }
}

actor SequenceMessagesLoader: SessionsMessagesLoading {
    var messagesByCall: [[APISessionMessage]]
    var loadCalls = 0

    init(messagesByCall: [[APISessionMessage]]) {
        self.messagesByCall = messagesByCall
    }

    func loadMessages(serverURLString: String, token: String, sessionID: String) async throws -> [APISessionMessage] {
        loadCalls += 1
        if messagesByCall.isEmpty {
            return []
        }
        if messagesByCall.count == 1 {
            return messagesByCall[0]
        }
        return messagesByCall.removeFirst()
    }

    func loadCallCount() -> Int {
        loadCalls
    }
}

struct SessionAwareMessagesLoader: SessionsMessagesLoading {
    func loadMessages(serverURLString: String, token: String, sessionID: String) async throws -> [APISessionMessage] {
        [
            APISessionMessage(
                id: "m-\(sessionID)",
                seq: 1,
                localId: nil,
                content: APIEncryptedMessageContent(t: "encrypted", c: "payload"),
                createdAt: 1,
                updatedAt: 1
            )
        ]
    }
}

actor CallOrderRecorder {
    var calls: [String] = []

    func append(_ call: String) {
        calls.append(call)
    }

    func snapshot() -> [String] {
        calls
    }
}

struct RecordingSessionPreDeleteKillUseCase: SessionPreDeleteKillingAction {
    let recorder: CallOrderRecorder

    func killSession(serverURLString: String, token: String, sessionID: String) async throws {
        await recorder.append("kill:\(sessionID)")
    }
}

struct RecordingSessionDeleteUseCase: SessionDeletingAction {
    let recorder: CallOrderRecorder

    func deleteSession(serverURLString: String, token: String, sessionID: String) async throws {
        await recorder.append("delete:\(sessionID)")
    }
}

enum MockSessionDeleteUseCaseError: Error, Sendable {
    case failed
}

struct MockSessionDeleteUseCase: SessionDeletingAction {
    let result: Result<Void, MockSessionDeleteUseCaseError>

    func deleteSession(serverURLString: String, token: String, sessionID: String) async throws {
        switch result {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }
}

enum MockSessionTitleUseCaseError: Error, Sendable {
    case failed
}

struct MockSessionTitleUseCase: SessionTitleUpdatingAction {
    let result: Result<Void, MockSessionTitleUseCaseError>

    func setSessionTitle(serverURLString: String, token: String, sessionID: String, title: String?) async throws {
        switch result {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }
}

enum MockSessionCodexThreadsLoaderError: Error, Sendable {
    case failed
}

struct MockSessionCodexThreadsLoader: SessionCodexThreadsLoading {
    let result: Result<[APICodexThreadSummary], MockSessionCodexThreadsLoaderError>

    func loadCodexThreads(serverURLString: String, token: String, sessionID: String, limit: Int, cwd: String?) async throws -> [APICodexThreadSummary] {
        switch result {
        case .success(let rows):
            return rows
        case .failure(let error):
            throw error
        }
    }
}

enum MockSessionClaudeSessionsLoaderError: Error, Sendable {
    case failed
}

struct MockSessionClaudeSessionsLoader: SessionClaudeSessionsLoading {
    let result: Result<[APIClaudeSessionSummary], MockSessionClaudeSessionsLoaderError>

    func loadClaudeSessions(serverURLString: String, token: String, sessionID: String, limit: Int, cwd: String?) async throws -> [APIClaudeSessionSummary] {
        switch result {
        case .success(let rows):
            return rows
        case .failure(let error):
            throw error
        }
    }
}

enum MockSessionSpawnUseCaseError: Error, Sendable {
    case failed
}

struct MockSessionSpawnUseCase: SessionSpawningAction {
    let result: Result<APISessionSpawnResult, MockSessionSpawnUseCaseError>

    func spawnSession(
        serverURLString: String,
        token: String,
        sessionID: String,
        directory: String,
        agent: APISessionSpawnAgent?,
        codexResumeThreadID: String?,
        claudeResumeSessionID: String?,
        approvedNewDirectoryCreation: Bool?
    ) async throws -> APISessionSpawnResult {
        switch result {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
}

enum MockSessionMessageSenderError: Error, Sendable {
    case failed
}

struct MockSessionMessageSender: SessionMessageSendingAction {
    let result: Result<APISessionSendMessageResult, MockSessionMessageSenderError>

    func sendMessage(
        serverURLString: String,
        token: String,
        sessionID: String,
        text: String,
        attachments: [SessionComposerImageAttachment],
        steerMode: APISessionSteerMode,
        permissionMode: APISessionMessagePermissionMode?,
        modelOverride: SessionMessageModelOverride,
        effortOverride: SessionMessageEffortOverride
    ) async throws -> APISessionSendMessageResult {
        switch result {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
}
