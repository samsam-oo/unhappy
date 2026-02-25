import Testing
import CoreKit
@testable import FeatureSessionTools

struct SessionInfoPresentationTests {
    @Test
    func makeBuildsMetadataAndAgentStateFields() {
        let session = APISession(
            id: "session-1",
            displayName: "Main",
            seq: 9,
            active: true,
            activeAt: 200,
            createdAt: 100,
            updatedAt: 300,
            metadataVersion: 2,
            metadata: #"{"machine":"m1","healthy":true,"count":3}"#,
            agentState: #"{"mode":"plan","step":2}"#,
            agentStateVersion: 7,
            dataEncryptionKey: "abcdefgh12345678",
            lastMessage: nil
        )

        let presentation = SessionInfoPresentationBuilder.make(from: session) { value in
            "ts:\(Int(value))"
        }

        #expect(presentation.sessionID == "session-1")
        #expect(presentation.title == "Main")
        #expect(presentation.sequenceText == "#9")
        #expect(presentation.createdAtText == "ts:100")
        #expect(presentation.activeAtText == "ts:200")
        #expect(presentation.updatedAtText == "ts:300")
        #expect(presentation.metadataFields.map(\.key) == ["count", "healthy", "machine"])
        #expect(presentation.agentStateFields.map(\.key) == ["mode", "step"])
        #expect(presentation.dataEncryptionKeyPreview == "abcd…5678")
    }

    @Test
    func makeTruncatesLongMetadataPreview() {
        let payload = String(repeating: "a", count: SessionInfoPresentationBuilder.metadataPreviewLimit + 10)
        let session = APISession(
            id: "session-2",
            active: false,
            activeAt: 1,
            createdAt: 1,
            updatedAt: 1,
            metadataVersion: 1,
            metadata: payload,
            agentState: nil,
            agentStateVersion: nil,
            dataEncryptionKey: nil,
            lastMessage: nil
        )

        let presentation = SessionInfoPresentationBuilder.make(from: session)

        #expect(presentation.metadataCharacterCount == payload.count)
        #expect(presentation.metadataTruncated == true)
        #expect(presentation.metadataPreview.count == SessionInfoPresentationBuilder.metadataPreviewLimit)
    }
}
