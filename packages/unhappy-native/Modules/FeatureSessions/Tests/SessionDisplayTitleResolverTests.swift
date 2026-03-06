import Testing
@testable import FeatureSessions
import CoreKit

struct SessionDisplayTitleResolverTests {
    @Test
    func resolvedDisplayTitleFallsBackToLastMessagePreview() {
        let session = APISession(
            id: "session-1",
            active: false,
            activeAt: 10,
            createdAt: 1,
            updatedAt: 20,
            metadataVersion: 1,
            metadata: "{}",
            dataEncryptionKey: nil,
            lastMessage: APIMessage(
                id: "message-1",
                seq: 1,
                content: APIEncryptedMessageContent(
                    t: "text",
                    c: "First request to the agent"
                ),
                createdAt: 1
            )
        )

        #expect(SessionDisplayTitleResolver.resolvedDisplayTitle(for: session) == "First request to the agent")
    }

    @Test
    func resolvedDisplayTitleKeepsMetadataSummaryAheadOfPreview() {
        let session = APISession(
            id: "session-2",
            active: true,
            activeAt: 10,
            createdAt: 1,
            updatedAt: 20,
            metadataVersion: 1,
            metadata: #"{"summary":{"text":"Saved summary title"}}"#,
            dataEncryptionKey: nil,
            lastMessage: APIMessage(
                id: "message-2",
                seq: 2,
                content: APIEncryptedMessageContent(
                    t: "text",
                    c: "This should stay secondary"
                ),
                createdAt: 2
            )
        )

        #expect(SessionDisplayTitleResolver.resolvedDisplayTitle(for: session) == "Saved summary title")
    }
}
