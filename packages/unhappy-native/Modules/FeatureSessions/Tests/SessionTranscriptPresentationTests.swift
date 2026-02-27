import Foundation
import Testing
@testable import FeatureSessions
import CoreKit

struct SessionTranscriptPresentationTests {
    @Test
    func readyEventIsHiddenFromTranscript() {
        let message = makeAgentEventMessage(eventType: "ready", message: nil)

        let presentation = SessionTranscriptPresentationBuilder.make(
            from: message,
            dataEncryptionKey: nil
        )

        #expect(presentation.entries.isEmpty)
    }

    @Test
    func genericProcessExitEventIsShownInTranscript() {
        let message = makeAgentEventMessage(
            eventType: "message",
            message: "Process exited unexpectedly"
        )

        let presentation = SessionTranscriptPresentationBuilder.make(
            from: message,
            dataEncryptionKey: nil
        )

        #expect(presentation.entries.count == 1)
        #expect(presentation.entries[0].body == "Process exited unexpectedly")
    }

    @Test
    func processExitWithReasonIsShownInTranscript() {
        let message = makeAgentEventMessage(
            eventType: "message",
            message: "Process exited: unsupported model gpt-5-codex"
        )

        let presentation = SessionTranscriptPresentationBuilder.make(
            from: message,
            dataEncryptionKey: nil
        )

        #expect(presentation.entries.count == 1)
        #expect(presentation.entries[0].body.contains("unsupported model"))
    }

    @Test
    func codexToolCallUsesReadableToolName() {
        let payload: [String: Any] = [
            "role": "agent",
            "content": [
                "type": "codex",
                "data": [
                    "type": "tool-call",
                    "name": "Read",
                    "input": [
                        "path": "/tmp/test.txt",
                    ],
                ],
            ],
        ]
        let message = makeMessage(from: payload)

        let presentation = SessionTranscriptPresentationBuilder.make(
            from: message,
            dataEncryptionKey: nil
        )

        #expect(presentation.entries.count == 1)
        #expect(presentation.entries[0].title == "Read Files")
    }

    @Test
    func codexMessageNestedTextIsExtracted() {
        let payload: [String: Any] = [
            "role": "agent",
            "content": [
                "type": "codex",
                "data": [
                    "type": "message",
                    "message": [
                        "content": [
                            [
                                "type": "text",
                                "text": "nested response",
                            ],
                        ],
                    ],
                ],
            ],
        ]
        let message = makeMessage(from: payload)

        let presentation = SessionTranscriptPresentationBuilder.make(
            from: message,
            dataEncryptionKey: nil
        )

        #expect(presentation.entries.count == 1)
        #expect(presentation.entries[0].body.contains("nested response"))
    }

    @Test
    func codexBootstrapThreadListMessageIsHidden() {
        let payload: [String: Any] = [
            "role": "agent",
            "content": [
                "type": "codex",
                "data": [
                    "type": "message",
                    "message": "Existing Codex sessions for this project:\n1. (untitled)",
                ],
            ],
        ]
        let message = makeMessage(from: payload)

        let presentation = SessionTranscriptPresentationBuilder.make(
            from: message,
            dataEncryptionKey: nil
        )

        #expect(presentation.entries.isEmpty)
    }

    private func makeAgentEventMessage(eventType: String, message: String?) -> APISessionMessage {
        var eventData: [String: Any] = ["type": eventType]
        if let message {
            eventData["message"] = message
        }
        let payload: [String: Any] = [
            "role": "agent",
            "content": [
                "type": "event",
                "data": eventData,
            ],
        ]
        return makeMessage(from: payload)
    }

    private func makeMessage(from payload: [String: Any]) -> APISessionMessage {
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [])) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? "{}"
        return APISessionMessage(
            id: UUID().uuidString,
            seq: 1,
            localId: nil,
            content: APIEncryptedMessageContent(t: "json", c: text),
            createdAt: 0,
            updatedAt: 0
        )
    }
}
