import Testing
@testable import FeatureSessions
import CoreKit

struct SessionFirstMessagePreviewResolverTests {
    @Test
    func resolveReturnsEarliestReadableMessageText() {
        let messages = [
            APISessionMessage(
                id: "message-2",
                seq: 2,
                localId: nil,
                content: APIEncryptedMessageContent(t: "text", c: "Second message"),
                createdAt: 2,
                updatedAt: 2
            ),
            APISessionMessage(
                id: "message-1",
                seq: 1,
                localId: nil,
                content: APIEncryptedMessageContent(t: "text", c: "First message"),
                createdAt: 1,
                updatedAt: 1
            ),
        ]

        #expect(
            SessionFirstMessagePreviewResolver.resolve(
                from: messages,
                dataEncryptionKey: nil
            ) == "First message"
        )
    }

    @Test
    func resolvePrefersStructuredPayloadText() {
        let messages = [
            APISessionMessage(
                id: "message-1",
                seq: 1,
                localId: nil,
                content: APIEncryptedMessageContent(
                    t: "json",
                    c: #"{"text":"Open the Tuist workspace"}"#
                ),
                createdAt: 1,
                updatedAt: 1
            ),
        ]

        #expect(
            SessionFirstMessagePreviewResolver.resolve(
                from: messages,
                dataEncryptionKey: nil
            ) == "Open the Tuist workspace"
        )
    }
}
