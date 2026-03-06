import Foundation

public struct SessionComposerImageAttachment: Identifiable, Equatable, Sendable {
    public let id: String
    public let data: Data
    public let mimeType: String

    public init(
        id: String = UUID().uuidString.lowercased(),
        data: Data,
        mimeType: String
    ) {
        self.id = id
        self.data = data
        self.mimeType = mimeType
    }

    public var dataURLString: String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }
}
