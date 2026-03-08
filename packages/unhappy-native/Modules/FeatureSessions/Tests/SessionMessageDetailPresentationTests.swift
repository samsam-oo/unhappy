import Foundation
import Testing
@testable import FeatureSessions
import CoreKit

struct SessionMessageDetailPresentationTests {
    @Test
    func makeProducesStructuredFields() {
        let message = APISessionMessage(
            id: "message-1",
            seq: 42,
            localId: "local-1",
            content: APIEncryptedMessageContent(type: "text", payload: "hello"),
            createdAt: 100,
            updatedAt: 200
        )

        let presentation = SessionMessageDetailPresentationBuilder.make(from: message) { value in
            "ts:\(Int(value))"
        }

        #expect(presentation.id == "message-1")
        #expect(presentation.sequenceText == "42")
        #expect(presentation.localID == "local-1")
        #expect(presentation.createdAtText == "ts:100")
        #expect(presentation.updatedAtText == "ts:200")
        #expect(presentation.contentType == "text")
        #expect(presentation.payloadPreview == "hello")
        #expect(presentation.payloadCharacterCount == 5)
        #expect(presentation.payloadTruncated == false)
        #expect(presentation.payloadFields.isEmpty)
    }

    @Test
    func makeTruncatesLargePayloadPreview() {
        let payload = String(repeating: "a", count: SessionMessageDetailPresentationBuilder.payloadPreviewLimit + 23)
        let message = APISessionMessage(
            id: "message-2",
            seq: 1,
            localId: nil,
            content: APIEncryptedMessageContent(type: "tool", payload: payload),
            createdAt: 100,
            updatedAt: 100
        )

        let presentation = SessionMessageDetailPresentationBuilder.make(from: message)

        #expect(presentation.payloadCharacterCount == payload.count)
        #expect(presentation.payloadTruncated == true)
        #expect(presentation.payloadPreview?.count == SessionMessageDetailPresentationBuilder.payloadPreviewLimit)
        #expect(presentation.payloadPreview == String(payload.prefix(SessionMessageDetailPresentationBuilder.payloadPreviewLimit)))
        #expect(presentation.payloadFields.isEmpty)
    }

    @Test
    func makeHandlesMissingContent() {
        let message = APISessionMessage(
            id: "message-3",
            seq: 3,
            localId: nil,
            content: nil,
            createdAt: 100,
            updatedAt: 100
        )

        let presentation = SessionMessageDetailPresentationBuilder.make(from: message)

        #expect(presentation.contentType == nil)
        #expect(presentation.payloadPreview == nil)
        #expect(presentation.payloadCharacterCount == 0)
        #expect(presentation.payloadTruncated == false)
        #expect(presentation.payloadFields.isEmpty)
    }

    @Test
    func makeParsesTopLevelJSONFields() {
        let payload = #"{"tool":"bash","exitCode":0,"success":true,"meta":{"cwd":"/tmp"}}"#
        let message = APISessionMessage(
            id: "message-4",
            seq: 4,
            localId: nil,
            content: APIEncryptedMessageContent(type: "tool", payload: payload),
            createdAt: 100,
            updatedAt: 100
        )

        let presentation = SessionMessageDetailPresentationBuilder.make(from: message)

        #expect(presentation.payloadFields.map(\.key) == ["exitCode", "meta", "success", "tool"])
        #expect(presentation.payloadFields.first(where: { $0.key == "tool" })?.value == "bash")
        #expect(presentation.payloadFields.first(where: { $0.key == "exitCode" })?.value == "0")
        #expect(presentation.payloadFields.first(where: { $0.key == "success" })?.value == "true")
        let metaValue = presentation.payloadFields.first(where: { $0.key == "meta" })?.value ?? ""
        #expect(metaValue.contains(#""cwd""#))
        #expect(metaValue.contains("tmp"))
    }
}
