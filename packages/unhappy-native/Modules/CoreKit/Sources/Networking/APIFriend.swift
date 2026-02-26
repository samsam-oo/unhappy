import Foundation

public enum APIRelationshipStatus: String, Decodable, Equatable, Sendable {
    case none
    case requested
    case pending
    case friend
    case rejected
}

public struct APIAvatarImage: Decodable, Equatable, Sendable {
    public let path: String
    public let url: String
    public let width: Int?
    public let height: Int?
    public let thumbhash: String?

    public init(
        path: String,
        url: String,
        width: Int?,
        height: Int?,
        thumbhash: String?
    ) {
        self.path = path
        self.url = url
        self.width = width
        self.height = height
        self.thumbhash = thumbhash
    }
}

public struct APIUserProfile: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let firstName: String
    public let lastName: String?
    public let avatar: APIAvatarImage?
    public let username: String
    public let bio: String?
    public let status: APIRelationshipStatus

    public init(
        id: String,
        firstName: String,
        lastName: String?,
        avatar: APIAvatarImage?,
        username: String,
        bio: String?,
        status: APIRelationshipStatus
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.avatar = avatar
        self.username = username
        self.bio = bio
        self.status = status
    }
}

public extension APIUserProfile {
    var displayName: String {
        let parts = [firstName, lastName].compactMap { value -> String? in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if parts.isEmpty {
            return username
        }
        return parts.joined(separator: " ")
    }
}
