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
        #expect(presentation.entries[0].sourceType == "message")
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
        #expect(presentation.entries[0].sourceType == "tool-call")
        #expect(presentation.entries[0].toolName == "read")
    }

    @Test
    func assistantToolResultKeepsToolUseIDAndReadableResultTitle() {
        let payload: [String: Any] = [
            "role": "agent",
            "content": [
                "type": "output",
                "data": [
                    "type": "assistant",
                    "message": [
                        "content": [
                            [
                                "type": "tool_use",
                                "id": "toolu_task_1",
                                "name": "Task",
                                "input": [
                                    "prompt": "Check logs",
                                ],
                            ],
                            [
                                "type": "tool_result",
                                "tool_use_id": "toolu_task_1",
                                "content": "done",
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

        #expect(presentation.entries.count == 2)
        #expect(presentation.entries[0].title == "Run Task")
        #expect(presentation.entries[0].toolUseID == "toolu_task_1")
        #expect(presentation.entries[0].sourceType == "tool_use")
        #expect(presentation.entries[0].toolName == "task")
        #expect(presentation.entries[1].title == "Run Task Result")
        #expect(presentation.entries[1].toolUseID == "toolu_task_1")
        #expect(presentation.entries[1].sourceType == "tool_result")
        #expect(presentation.entries[1].toolName == "task")
    }

    @Test
    func outputUserToolResultKeepsToolUseID() {
        let payload: [String: Any] = [
            "role": "agent",
            "content": [
                "type": "output",
                "data": [
                    "type": "user",
                    "message": [
                        "role": "user",
                        "content": [
                            [
                                "type": "tool_result",
                                "tool_use_id": "toolu_subagent_1",
                                "content": [
                                    [
                                        "type": "text",
                                        "text": "Sub-agent finished.",
                                    ],
                                ],
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
        #expect(presentation.entries[0].kind == .toolResult)
        #expect(presentation.entries[0].toolUseID == "toolu_subagent_1")
        #expect(presentation.entries[0].sourceType == "tool_result")
        #expect(presentation.entries[0].isSidechain == false)
    }

    @Test
    func outputUserToolResultWithParentToolUseIdIsMarkedAsSidechain() {
        let payload: [String: Any] = [
            "role": "agent",
            "content": [
                "type": "output",
                "data": [
                    "type": "user",
                    "parentToolUseId": "toolu_parent_task_0",
                    "message": [
                        "role": "user",
                        "content": [
                            [
                                "type": "tool_result",
                                "tool_use_id": "toolu_subagent_2",
                                "content": "done",
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
        #expect(presentation.entries[0].kind == .toolResult)
        #expect(presentation.entries[0].isSidechain == true)
    }

    @Test
    func outputUserToolResultWithParentToolUseIDIsMarkedAsSidechain() {
        let payload: [String: Any] = [
            "role": "agent",
            "content": [
                "type": "output",
                "data": [
                    "type": "user",
                    "parent_tool_use_id": "toolu_parent_task_1",
                    "message": [
                        "role": "user",
                        "content": [
                            [
                                "type": "tool_result",
                                "tool_use_id": "toolu_subagent_3",
                                "content": "done",
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
        #expect(presentation.entries[0].kind == .toolResult)
        #expect(presentation.entries[0].isSidechain == true)
    }

    @Test
    func outputUserToolResultKeepsExplicitToolName() {
        let payload: [String: Any] = [
            "role": "agent",
            "content": [
                "type": "output",
                "data": [
                    "type": "user",
                    "message": [
                        "role": "user",
                        "content": [
                            [
                                "type": "tool_result",
                                "tool_use_id": "toolu_task_2",
                                "name": "Task",
                                "content": "done",
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
        #expect(presentation.entries[0].kind == .toolResult)
        #expect(presentation.entries[0].toolName == "task")
    }

    @Test
    func latestItemStartedCommandExecutionBecomesToolCallEntry() {
        let payload: [String: Any] = [
            "role": "agent",
            "content": [
                "type": "codex",
                "data": [
                    "type": "item_started",
                    "item": [
                        "type": "commandExecution",
                        "id": "item_cmd_1",
                        "command": "rg markdown Sources",
                        "cwd": "/tmp/project",
                        "commandActions": [
                            [
                                "type": "search",
                                "command": "rg markdown Sources",
                                "query": "markdown",
                                "path": "Sources",
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
        #expect(presentation.entries[0].kind == .toolCall)
        #expect(presentation.entries[0].toolName == "codexbash")
        #expect(presentation.entries[0].sourceType == "item_started")
    }

    @Test
    func latestTurnDiffBecomesToolResultEntry() {
        let payload: [String: Any] = [
            "role": "agent",
            "content": [
                "type": "codex",
                "data": [
                    "type": "turn_diff",
                    "unified_diff": "@@ -1,1 +1,2 @@\n-import Foundation\n+import Foundation\n+import SwiftUI",
                ],
            ],
        ]
        let message = makeMessage(from: payload)

        let presentation = SessionTranscriptPresentationBuilder.make(
            from: message,
            dataEncryptionKey: nil
        )

        #expect(presentation.entries.count == 1)
        #expect(presentation.entries[0].kind == .toolResult)
        #expect(presentation.entries[0].title == "Turn Diff")
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

    @Test
    func codexTaskStartedShowsThinkingEntry() {
        let payload: [String: Any] = [
            "role": "agent",
            "content": [
                "type": "codex",
                "data": [
                    "type": "task_started",
                ],
            ],
        ]
        let message = makeMessage(from: payload)

        let presentation = SessionTranscriptPresentationBuilder.make(
            from: message,
            dataEncryptionKey: nil
        )

        #expect(presentation.entries.count == 1)
        #expect(presentation.entries[0].kind == .thinking)
    }

    @Test
    func userInputImageChunkShowsImagePlaceholder() {
        let payload: [String: Any] = [
            "role": "user",
            "content": [
                [
                    "type": "input_image",
                    "image_url": "data:image/png;base64,AAAA",
                ],
                [
                    "type": "input_text",
                    "text": "Please inspect this screenshot.",
                ],
            ],
        ]
        let message = makeMessage(from: payload)

        let presentation = SessionTranscriptPresentationBuilder.make(
            from: message,
            dataEncryptionKey: nil
        )

        #expect(presentation.entries.count == 2)
        #expect(presentation.entries[0].role == .user)
        #expect(presentation.entries[0].kind == .text)
        #expect(presentation.entries[0].body == "[Image #1]")
        #expect(presentation.entries[1].body == "Please inspect this screenshot.")
    }

    @Test
    func emptyCompletedToolResultIsHidden() {
        let payload: [String: Any] = [
            "role": "agent",
            "content": [
                "type": "codex",
                "data": [
                    "type": "tool-result",
                    "name": "CodexReasoning",
                    "output": [
                        "content": "",
                        "status": "completed",
                    ],
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

    @Test
    func terminalOutputStripsAnsiEscapes() {
        let payload: [String: Any] = [
            "role": "agent",
            "content": [
                "type": "codex",
                "data": [
                    "type": "terminal-output",
                    "data": "\u{001B}[32mExplored\u{001B}[0m path",
                ],
            ],
        ]
        let message = makeMessage(from: payload)

        let presentation = SessionTranscriptPresentationBuilder.make(
            from: message,
            dataEncryptionKey: nil
        )

        #expect(presentation.entries.count == 1)
        #expect(presentation.entries[0].body == "Explored path")
        #expect(presentation.entries[0].title == "Streaming output")
    }

    @Test
    func terminalOutputPreservesCallID() {
        let payload: [String: Any] = [
            "role": "agent",
            "content": [
                "type": "codex",
                "data": [
                    "type": "terminal-output",
                    "callId": "tool-stream-1",
                    "data": " user",
                ],
            ],
        ]
        let message = makeMessage(from: payload)

        let presentation = SessionTranscriptPresentationBuilder.make(
            from: message,
            dataEncryptionKey: nil
        )

        #expect(presentation.entries.count == 1)
        #expect(presentation.entries[0].toolUseID == "tool-stream-1")
        #expect(presentation.entries[0].body == " user")
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
            content: APIEncryptedMessageContent(type: "json", payload: text),
            createdAt: 0,
            updatedAt: 0
        )
    }
}
