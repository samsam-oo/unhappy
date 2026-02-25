import Foundation

public enum APIFeedBody: Decodable, Equatable, Sendable {
    case friendRequest(uid: String)
    case friendAccepted(uid: String)
    case text(text: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case uid
        case text
    }

    private enum Kind: String, Decodable {
        case friendRequest = "friend_request"
        case friendAccepted = "friend_accepted"
        case text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .friendRequest:
            self = .friendRequest(uid: try container.decode(String.self, forKey: .uid))
        case .friendAccepted:
            self = .friendAccepted(uid: try container.decode(String.self, forKey: .uid))
        case .text:
            self = .text(text: try container.decode(String.self, forKey: .text))
        }
    }
}

public struct APIFeedItem: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let body: APIFeedBody
    public let repeatKey: String?
    public let cursor: String
    public let createdAt: TimeInterval

    public init(
        id: String,
        body: APIFeedBody,
        repeatKey: String?,
        cursor: String,
        createdAt: TimeInterval
    ) {
        self.id = id
        self.body = body
        self.repeatKey = repeatKey
        self.cursor = cursor
        self.createdAt = createdAt
    }
}

public struct APIFeedPage: Decodable, Equatable, Sendable {
    public let items: [APIFeedItem]
    public let hasMore: Bool

    public init(items: [APIFeedItem], hasMore: Bool) {
        self.items = items
        self.hasMore = hasMore
    }
}
