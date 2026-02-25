import Foundation
import CoreKit

public struct InboxItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let timestamp: Date

    public init(id: String, title: String, subtitle: String, timestamp: Date) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.timestamp = timestamp
    }
}

public protocol InboxLoadingAction: Sendable {
    func loadInboxItems(serverURLString: String, token: String) async throws -> [InboxItem]
}

public enum InboxLoadingError: LocalizedError, Equatable {
    case missingToken
    case invalidServerURL

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "API token is required"
        case .invalidServerURL:
            return "Invalid server URL"
        }
    }
}

public actor InboxLoadUseCase: InboxLoadingAction {
    private struct RequestKey: Hashable, Sendable {
        let serverURLString: String
        let token: String
        let limit: Int
    }

    private let service: any FeedFetching
    private let limit: Int
    private var inFlightTasks: [RequestKey: Task<[InboxItem], Error>] = [:]

    public init(service: any FeedFetching, limit: Int = 50) {
        self.service = service
        self.limit = limit
    }

    public func loadInboxItems(serverURLString: String, token: String) async throws -> [InboxItem] {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw InboxLoadingError.missingToken
        }

        let normalizedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedURL.isEmpty,
            let serverURL = URL(string: normalizedURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw InboxLoadingError.invalidServerURL
        }

        let boundedLimit = min(max(limit, 1), 200)
        let requestKey = RequestKey(
            serverURLString: normalizedURL,
            token: normalizedToken,
            limit: boundedLimit
        )
        if let inFlightTask = inFlightTasks[requestKey] {
            return try await inFlightTask.value
        }

        let service = self.service
        let task = Task<[InboxItem], Error> {
            let page = try await service.fetchFeed(
                serverURL: serverURL,
                token: normalizedToken,
                before: nil,
                after: nil,
                limit: boundedLimit
            )
            return page.items.map(Self.makeInboxItem(from:))
        }

        inFlightTasks[requestKey] = task
        defer { inFlightTasks[requestKey] = nil }
        return try await task.value
    }
}

private extension InboxLoadUseCase {
    static func makeInboxItem(from row: APIFeedItem) -> InboxItem {
        let timestamp = Date(timeIntervalSince1970: row.createdAt / 1000)

        let title: String
        let subtitle: String
        switch row.body {
        case .friendRequest(let uid):
            title = "Friend request"
            subtitle = "From \(uid)"
        case .friendAccepted(let uid):
            title = "Friend request accepted"
            subtitle = uid
        case .text(let text):
            title = text
            subtitle = "Feed update"
        }

        return InboxItem(
            id: row.id,
            title: title,
            subtitle: subtitle,
            timestamp: timestamp
        )
    }
}
