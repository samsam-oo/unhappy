import Foundation
import Combine
@testable import FeatureSessions
import FeatureNewSession
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

struct MockSessionsServiceForValidation: SessionsFetching, SessionsPagingFetching, SessionDeleting {
    func fetchSessions(serverURL: URL, token: String) async throws -> [APISession] {
        []
    }

    func fetchSessionsPage(serverURL: URL, token: String, cursor: String?, limit: Int) async throws -> APISessionsPage {
        APISessionsPage(sessions: [], nextCursor: nil, hasNext: false)
    }

    func deleteSession(serverURL: URL, token: String, sessionID: String) async throws {}
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

struct SequenceSessionsPoller: SessionsPolling {
    let emissions: [[APISession]]

    func makePollingStream(
        serverURLString: String,
        token: String,
        interval: Duration
    ) async -> AsyncThrowingStream<[APISession], Error> {
        AsyncThrowingStream { continuation in
            for rows in emissions {
                continuation.yield(rows)
            }
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

struct RecordingSessionDeleteUseCase: SessionDeletingAction {
    let recorder: SessionDeleteRecorder

    func deleteSession(serverURLString: String, token: String, sessionID: String) async throws {
        await recorder.append("delete:\(sessionID)")
    }
}

actor SessionDeleteRecorder {
    var calls: [String] = []

    func append(_ call: String) {
        calls.append(call)
    }

    func snapshot() -> [String] {
        calls
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

enum MockUpstreamSessionsLoaderError: Error, Sendable {
    case failed
}

struct MockUpstreamSessionsLoader: SessionUpstreamSessionsLoadingAction {
    let result: Result<[SessionLinkedUpstreamSession], MockUpstreamSessionsLoaderError>

    func loadUpstreamSessions(
        serverURLString: String,
        token: String,
        projects: [SessionMachineProject]
    ) async throws -> [SessionLinkedUpstreamSession] {
        switch result {
        case .success(let rows):
            return rows
        case .failure(let error):
            throw error
        }
    }
}

actor SequenceUpstreamSessionsLoader: SessionUpstreamSessionsLoadingAction {
    var results: [Result<[SessionLinkedUpstreamSession], MockUpstreamSessionsLoaderError>]

    init(results: [Result<[SessionLinkedUpstreamSession], MockUpstreamSessionsLoaderError>]) {
        self.results = results
    }

    func loadUpstreamSessions(
        serverURLString: String,
        token: String,
        projects: [SessionMachineProject]
    ) async throws -> [SessionLinkedUpstreamSession] {
        if results.isEmpty {
            return []
        }
        let next = results.removeFirst()
        switch next {
        case .success(let rows):
            return rows
        case .failure(let error):
            throw error
        }
    }
}

actor RecordingUpstreamSessionsLoader: SessionUpstreamSessionsLoadingAction {
    private var calls = 0
    private var requestedProjects: [[SessionMachineProject]] = []
    let result: Result<[SessionLinkedUpstreamSession], MockUpstreamSessionsLoaderError>

    init(result: Result<[SessionLinkedUpstreamSession], MockUpstreamSessionsLoaderError>) {
        self.result = result
    }

    func loadUpstreamSessions(
        serverURLString: String,
        token: String,
        projects: [SessionMachineProject]
    ) async throws -> [SessionLinkedUpstreamSession] {
        calls += 1
        requestedProjects.append(projects)
        switch result {
        case .success(let rows):
            return rows
        case .failure(let error):
            throw error
        }
    }

    func callCount() -> Int {
        calls
    }

    func requestedProjectSnapshots() -> [[SessionMachineProject]] {
        requestedProjects
    }
}

enum MockProjectsLoaderError: Error, Sendable {
    case failed
}

actor SequenceProjectsLoader: SessionProjectsLoadingAction {
    var results: [Result<[SessionMachineProject], MockProjectsLoaderError>]

    init(results: [Result<[SessionMachineProject], MockProjectsLoaderError>]) {
        self.results = results
    }

    func loadProjects(serverURLString: String, token: String) async throws -> [SessionMachineProject] {
        if results.isEmpty {
            return []
        }
        let next = results.count == 1 ? results[0] : results.removeFirst()
        switch next {
        case .success(let projects):
            return projects
        case .failure(let error):
            throw error
        }
    }
}

actor RecordingProjectsLoader: SessionProjectsLoadingAction {
    private var calls = 0
    let result: Result<[SessionMachineProject], MockProjectsLoaderError>

    init(result: Result<[SessionMachineProject], MockProjectsLoaderError>) {
        self.result = result
    }

    func loadProjects(serverURLString: String, token: String) async throws -> [SessionMachineProject] {
        calls += 1
        switch result {
        case .success(let projects):
            return projects
        case .failure(let error):
            throw error
        }
    }

    func callCount() -> Int {
        calls
    }
}

enum MockProjectRemoverError: Error, Sendable {
    case failed
}

struct MockProjectRemover: SessionProjectRemovingAction {
    let result: Result<SessionMachineProject, MockProjectRemoverError>

    func removeProject(
        serverURLString: String,
        token: String,
        machineID: String,
        path: String,
        wrappedMachineDataEncryptionKey: String?
    ) async throws -> SessionMachineProject {
        switch result {
        case .success(let project):
            return project
        case .failure(let error):
            throw error
        }
    }
}
