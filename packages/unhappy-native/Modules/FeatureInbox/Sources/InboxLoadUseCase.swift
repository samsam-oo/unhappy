import Foundation

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
    func loadInboxItems() async throws -> [InboxItem]
}

public actor InboxLoadUseCase: InboxLoadingAction {
    public init() {}

    public func loadInboxItems() async throws -> [InboxItem] {
        []
    }
}
