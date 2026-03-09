import Foundation
import CoreKit

extension SessionTranscriptPresentationBuilder {
    static func parseAgentRecord(
        _ record: [String: Any],
        messageID: String
    ) -> [SessionTranscriptEntry] {
        guard let content = record["content"] as? [String: Any],
              let contentType = content["type"] as? String else {
            return [
                makeEntry(
                    id: "\(messageID)-agent",
                    role: .agent,
                    kind: .raw,
                    title: "Agent payload",
                    body: stringify(record["content"])
                )
            ]
        }

        switch contentType {
        case "output":
            return parseOutputEnvelope(
                content["data"],
                messageID: messageID
            )
        case "event":
            return parseEventEnvelope(
                content["data"],
                messageID: messageID
            )
        case "codex", "acp":
            return parseACPEnvelope(
                content["data"],
                messageID: messageID
            )
        default:
            return [
                makeEntry(
                    id: "\(messageID)-agent",
                    role: .agent,
                    kind: .raw,
                    title: "Agent \(contentType)",
                    body: stringify(content)
                )
            ]
        }
    }

    private static func parseOutputEnvelope(
        _ data: Any?,
        messageID: String
    ) -> [SessionTranscriptEntry] {
        guard let dictionary = data as? [String: Any] else {
            return [
                makeEntry(
                    id: "\(messageID)-output",
                    role: .agent,
                    kind: .raw,
                    title: "Output",
                    body: stringify(data)
                )
            ]
        }

        guard let type = dictionary["type"] as? String else {
            return [
                makeEntry(
                    id: "\(messageID)-output",
                    role: .agent,
                    kind: .raw,
                    title: "Output",
                    body: stringify(dictionary)
                )
            ]
        }

        let isSidechain = extractIsSidechain(from: dictionary)

        switch type {
        case "assistant":
            return parseAssistantMessage(
                dictionary["message"],
                messageID: messageID,
                isSidechain: isSidechain
            )
        case "user":
            return parseOutputUserMessage(
                dictionary["message"],
                messageID: messageID,
                isSidechain: isSidechain
            )
        case "summary":
            let summary = normalizedText(dictionary["summary"]) ?? stringify(dictionary["summary"])
            return [
                makeEntry(
                    id: "\(messageID)-summary",
                    role: .agent,
                    kind: .event,
                    title: "Summary",
                    body: summary,
                    isSidechain: isSidechain
                )
            ]
        case "result", "system":
            return [
                makeEntry(
                    id: "\(messageID)-\(type)",
                    role: .system,
                    kind: .event,
                    title: type.capitalized,
                    body: stringify(dictionary),
                    isSidechain: isSidechain
                )
            ]
        default:
            return [
                makeEntry(
                    id: "\(messageID)-output-\(type)",
                    role: .agent,
                    kind: .raw,
                    title: "Output \(type)",
                    body: stringify(dictionary),
                    isSidechain: isSidechain
                )
            ]
        }
    }

    private static func parseAssistantMessage(
        _ messageValue: Any?,
        messageID: String,
        isSidechain: Bool = false
    ) -> [SessionTranscriptEntry] {
        guard let message = messageValue as? [String: Any] else {
            return [
                makeEntry(
                    id: "\(messageID)-assistant",
                    role: .agent,
                    kind: .raw,
                    title: "Assistant",
                    body: stringify(messageValue),
                    isSidechain: isSidechain
                )
            ]
        }

        guard let contentArray = message["content"] as? [Any], !contentArray.isEmpty else {
            return [
                makeEntry(
                    id: "\(messageID)-assistant",
                    role: .agent,
                    kind: .raw,
                    title: "Assistant",
                    body: stringify(message),
                    isSidechain: isSidechain
                )
            ]
        }

        var entries: [SessionTranscriptEntry] = []
        var toolNamesByID: [String: String] = [:]
        var toolTitlesByID: [String: String] = [:]
        for (index, item) in contentArray.enumerated() {
            guard let chunk = item as? [String: Any],
                  let type = chunk["type"] as? String else {
                entries.append(
                    makeEntry(
                        id: "\(messageID)-assistant-\(index)",
                        role: .agent,
                        kind: .raw,
                        title: "Chunk",
                        body: stringify(item),
                        isSidechain: isSidechain
                    )
                )
                continue
            }

            switch type {
            case "text", "output_text", "input_text":
                let text = normalizedText(chunk["text"]) ?? stringify(chunk)
                entries.append(
                    makeEntry(
                        id: "\(messageID)-assistant-\(index)",
                        role: .agent,
                        kind: .text,
                        title: nil,
                        body: text,
                        sourceType: type,
                        isSidechain: isSidechain
                    )
                )
            case "thinking", "reasoning", "reasoning_text", "output_reasoning":
                let text = normalizedText(chunk["thinking"]) ?? normalizedText(chunk["text"]) ?? stringify(chunk)
                entries.append(
                    makeEntry(
                        id: "\(messageID)-assistant-\(index)",
                        role: .agent,
                        kind: .thinking,
                        title: "Thinking",
                        body: text,
                        sourceType: type,
                        isSidechain: isSidechain
                    )
                )
            case "tool_use", "tool-call":
                let name = normalizedText(chunk["name"]) ?? "Tool"
                let toolUseID = extractToolUseID(from: chunk)
                let inputText = stringify(chunk["input"])
                let summarizedTitle = SessionTranscriptRichContentParser.summaryTitle(
                    for: makeEntry(
                        id: "\(messageID)-assistant-\(index)-summary",
                        role: .agent,
                        kind: .toolCall,
                        title: toolDisplayName(name),
                        body: inputText,
                        toolUseID: toolUseID,
                        sourceType: type,
                        toolName: name,
                        isSidechain: isSidechain
                    )
                ) ?? toolDisplayName(name)
                if let toolUseID {
                    toolNamesByID[toolUseID] = name
                    toolTitlesByID[toolUseID] = summarizedTitle
                }
                entries.append(
                    makeEntry(
                        id: "\(messageID)-assistant-\(index)",
                        role: .agent,
                        kind: .toolCall,
                        title: summarizedTitle,
                        body: inputText,
                        toolUseID: toolUseID,
                        sourceType: type,
                        toolName: name,
                        isSidechain: isSidechain
                    )
                )
            case "tool_result", "tool-call-result":
                let toolUseID = extractToolUseID(from: chunk)
                let linkedToolName = toolUseID.flatMap { toolNamesByID[$0] }
                let linkedToolTitle = toolUseID.flatMap { toolTitlesByID[$0] }
                let title = linkedToolTitle.map { "\($0) Result" } ??
                    linkedToolName.map { "\(toolDisplayName($0)) Result" } ??
                    "Tool result"
                let outputText = stringifyToolResultContent(chunk["content"] ?? chunk["output"])
                entries.append(
                    makeEntry(
                        id: "\(messageID)-assistant-\(index)",
                        role: .agent,
                        kind: .toolResult,
                        title: title,
                        body: outputText,
                        toolUseID: toolUseID,
                        sourceType: type,
                        toolName: linkedToolName,
                        isSidechain: isSidechain
                    )
                )
            default:
                entries.append(
                    makeEntry(
                        id: "\(messageID)-assistant-\(index)",
                        role: .agent,
                        kind: .raw,
                        title: "Chunk \(type)",
                        body: stringify(chunk),
                        isSidechain: isSidechain
                    )
                )
            }
        }
        return entries
    }

    private static func parseOutputUserMessage(
        _ messageValue: Any?,
        messageID: String,
        isSidechain: Bool = false
    ) -> [SessionTranscriptEntry] {
        guard let message = messageValue as? [String: Any] else {
            return [
                makeEntry(
                    id: "\(messageID)-output-user",
                    role: .user,
                    kind: .raw,
                    title: "User output",
                    body: stringify(messageValue),
                    isSidechain: isSidechain
                )
            ]
        }

        if let contentString = normalizedText(message["content"]) {
            return [
                makeEntry(
                    id: "\(messageID)-output-user",
                    role: .user,
                    kind: .text,
                    title: nil,
                    body: contentString,
                    isSidechain: isSidechain
                )
            ]
        }

        if let contentArray = message["content"] as? [Any], !contentArray.isEmpty {
            var entries: [SessionTranscriptEntry] = []
            var imageIndex = 0
            for (index, item) in contentArray.enumerated() {
                if let chunk = item as? [String: Any],
                   let type = (chunk["type"] as? String)?.lowercased() {
                    if type == "tool_result" {
                        let toolUseID = extractToolUseID(from: chunk)
                        let toolName = normalizedText(chunk["name"])
                        entries.append(
                            makeEntry(
                                id: "\(messageID)-output-user-\(index)",
                                role: .agent,
                                kind: .toolResult,
                                title: "Tool result",
                                body: stringifyToolResultContent(chunk["content"]),
                                toolUseID: toolUseID,
                                sourceType: type,
                                toolName: toolName,
                                isSidechain: isSidechain
                            )
                        )
                        continue
                    }

                    if type == "text" || type == "input_text" {
                        let text =
                            normalizedText(chunk["text"]) ??
                            normalizedText(chunk["input_text"]) ??
                            extractMessageText(from: chunk["content"]) ??
                            stringify(chunk)
                        entries.append(
                            makeEntry(
                                id: "\(messageID)-output-user-\(index)",
                                role: .user,
                                kind: .text,
                                title: nil,
                                body: text,
                                isSidechain: isSidechain
                            )
                        )
                        continue
                    }

                    if type == "image" || type == "input_image" || type == "image_url" || type.contains("image") {
                        imageIndex += 1
                        entries.append(
                            makeEntry(
                                id: "\(messageID)-output-user-\(index)",
                                role: .user,
                                kind: .text,
                                title: nil,
                                body: imagePlaceholderText(index: imageIndex),
                                isSidechain: isSidechain
                            )
                        )
                        continue
                    }
                }

                entries.append(
                    makeEntry(
                        id: "\(messageID)-output-user-\(index)",
                        role: .agent,
                        kind: .raw,
                        title: "Chunk",
                        body: stringify(item),
                        isSidechain: isSidechain
                    )
                )
            }
            return entries
        }

        return [
            makeEntry(
                id: "\(messageID)-output-user",
                role: .user,
                kind: .raw,
                title: "User output",
                body: stringify(message),
                isSidechain: isSidechain
            )
        ]
    }

    private static func parseEventEnvelope(
        _ data: Any?,
        messageID: String
    ) -> [SessionTranscriptEntry] {
        if let dictionary = data as? [String: Any] {
            let type = (normalizedText(dictionary["type"]) ?? "event").lowercased()
            let messageText = normalizedText(dictionary["message"])
            if type == "ready" {
                return []
            }
            let body = messageText ?? stringify(dictionary)
            return [
                makeEntry(
                    id: "\(messageID)-event",
                    role: .system,
                    kind: .event,
                    title: type == "message"
                        ? nil
                        : type.replacingOccurrences(of: "_", with: " ").capitalized,
                    body: body,
                    sourceType: type
                )
            ]
        }
        return [
            makeEntry(
                id: "\(messageID)-event",
                role: .system,
                kind: .event,
                title: "Event",
                body: stringify(data)
            )
        ]
    }

    private static func parseACPEnvelope(
        _ data: Any?,
        messageID: String
    ) -> [SessionTranscriptEntry] {
        guard let dictionary = data as? [String: Any] else {
            return [
                makeEntry(
                    id: "\(messageID)-acp",
                    role: .agent,
                    kind: .raw,
                    title: "Agent output",
                    body: stringify(data)
                )
            ]
        }

        let type = normalizedText(dictionary["type"]) ?? "unknown"
        let isSidechain = extractIsSidechain(from: dictionary)
        let threadID = extractThreadID(from: dictionary)
        switch type {
        case "message", "reasoning":
            let text =
                extractMessageText(from: dictionary["message"]) ??
                extractMessageText(from: dictionary["text"]) ??
                extractMessageText(from: dictionary["content"]) ??
                stringify(dictionary)
            if type == "message",
               text.hasPrefix("Existing Codex sessions for this project:") {
                return []
            }
            return [
                makeEntry(
                    id: "\(messageID)-acp-\(type)",
                    role: .agent,
                    kind: .text,
                    title: type == "reasoning" ? "Reasoning" : nil,
                    body: text,
                    sourceType: type,
                    isSidechain: isSidechain,
                    threadID: threadID
                )
            ]
        case "thinking":
            let text = normalizedText(dictionary["text"]) ?? normalizedText(dictionary["message"]) ?? stringify(dictionary)
            return [
                makeEntry(
                    id: "\(messageID)-acp-thinking",
                    role: .agent,
                    kind: .thinking,
                    title: "Thinking",
                    body: text,
                    sourceType: type,
                    isSidechain: isSidechain,
                    threadID: threadID
                )
            ]
        case "tool-call":
            let name = normalizedText(dictionary["name"]) ?? "Tool"
            let toolUseID = extractToolUseID(from: dictionary)
            let reasoningTitle = codexReasoningTitle(from: dictionary["input"])
            let body = stringify(dictionary["input"])
            let title = reasoningTitle ?? (
                SessionTranscriptRichContentParser.summaryTitle(
                    for: makeEntry(
                        id: "\(messageID)-acp-tool-call-summary",
                        role: .agent,
                        kind: .toolCall,
                        title: toolDisplayName(name),
                        body: body,
                        toolUseID: toolUseID,
                        sourceType: type,
                        toolName: name,
                        isSidechain: isSidechain,
                        threadID: threadID
                    )
                ) ?? toolDisplayName(name)
            )
            return [
                makeEntry(
                    id: "\(messageID)-acp-tool-call",
                    role: .agent,
                    kind: .toolCall,
                    title: title,
                    body: body,
                    toolUseID: toolUseID,
                    sourceType: type,
                    toolName: name,
                    isSidechain: isSidechain,
                    threadID: threadID
                )
            ]
        case "tool-result", "tool-call-result":
            if shouldHideToolResult(dictionary["output"] ?? dictionary["content"]) {
                return []
            }
            let toolUseID = extractToolUseID(from: dictionary)
            let name = normalizedText(dictionary["name"])
            let title = name.map { "\(toolDisplayName($0)) Result" } ?? "Tool Result"
            return [
                makeEntry(
                    id: "\(messageID)-acp-tool-result",
                    role: .agent,
                    kind: .toolResult,
                    title: title,
                    body: stringifyToolResultContent(dictionary["output"] ?? dictionary["content"]),
                    toolUseID: toolUseID,
                    sourceType: type,
                    toolName: name,
                    isSidechain: isSidechain,
                    threadID: threadID
                )
            ]
        case "terminal-output":
            let rawOutput = dictionary["data"] ?? dictionary["output"]
            let output: String = {
                if let direct = rawOutput as? String {
                    return sanitizeText(direct)
                }
                return stringifyToolResultContent(rawOutput)
            }()
            if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return []
            }
            let toolUseID = extractToolUseID(from: dictionary)
            return [
                makeEntry(
                    id: "\(messageID)-acp-terminal",
                    role: .agent,
                    kind: .raw,
                    title: "Streaming output",
                    body: output,
                    toolUseID: toolUseID,
                    sourceType: type,
                    preserveWhitespace: true,
                    isSidechain: isSidechain,
                    threadID: threadID
                )
            ]
        case "tool-stream":
            let output: String = {
                if let direct = dictionary["output"] as? String {
                    return sanitizeText(direct)
                }
                if let direct = dictionary["text"] as? String {
                    return sanitizeText(direct)
                }
                if let normalized = normalizedText(dictionary["output"] ?? dictionary["text"]) {
                    return sanitizeText(normalized)
                }
                return ""
            }()
            if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return []
            }
            let toolUseID = extractToolUseID(from: dictionary)
            return [
                makeEntry(
                    id: "\(messageID)-acp-tool-stream",
                    role: .agent,
                    kind: .raw,
                    title: "Streaming output",
                    body: output,
                    toolUseID: toolUseID,
                    sourceType: type,
                    preserveWhitespace: true,
                    isSidechain: isSidechain,
                    threadID: threadID
                )
            ]
        case "permission-request":
            let tool = normalizedText(dictionary["toolName"]) ?? "Tool"
            let description = normalizedText(dictionary["description"]) ?? stringify(dictionary["options"])
            return [
                makeEntry(
                    id: "\(messageID)-acp-permission",
                    role: .system,
                    kind: .event,
                    title: "Approval needed: \(tool)",
                    body: description,
                    sourceType: type,
                    isSidechain: isSidechain,
                    threadID: threadID
                )
            ]
        case "task_started":
            let taskSummary =
                normalizedText(dictionary["description"]) ??
                normalizedText(dictionary["prompt"]) ??
                normalizedText(dictionary["message"]) ??
                normalizedText(dictionary["title"]) ??
                normalizedText(dictionary["task"]) ??
                "Thinking…"
            return [
                makeEntry(
                    id: "\(messageID)-acp-task",
                    role: .agent,
                    kind: .thinking,
                    title: nil,
                    body: taskSummary,
                    sourceType: type,
                    isSidechain: isSidechain,
                    threadID: threadID
                )
            ]
        case "task_complete", "turn_aborted":
            return []
        case "token_count":
            return []
        case "turn_diff":
            let diff =
                normalizedText(dictionary["unified_diff"]) ??
                normalizedText(dictionary["diff"]) ??
                stringify(dictionary)
            return [
                makeEntry(
                    id: "\(messageID)-acp-turn-diff",
                    role: .agent,
                    kind: .toolResult,
                    title: "Turn Diff",
                    body: diff,
                    sourceType: type,
                    toolName: "codexdiff",
                    isSidechain: isSidechain,
                    threadID: threadID
                )
            ]
        case "item_started", "item_completed":
            return parseLatestThreadItem(
                dictionary["item"],
                eventType: type,
                messageID: messageID,
                isSidechain: isSidechain,
                threadID: threadID
            )
        default:
            return [
                makeEntry(
                    id: "\(messageID)-acp-raw",
                    role: .agent,
                    kind: .raw,
                    title: "Agent \(type)",
                    body: stringify(dictionary),
                    sourceType: type,
                    isSidechain: isSidechain,
                    threadID: threadID
                )
            ]
        }
}

    private static func parseLatestThreadItem(
        _ itemValue: Any?,
        eventType: String,
        messageID: String,
        isSidechain: Bool,
        threadID: String?
    ) -> [SessionTranscriptEntry] {
        guard let item = itemValue as? [String: Any] else {
            return [
                makeEntry(
                    id: "\(messageID)-latest-item-raw",
                    role: .agent,
                    kind: .raw,
                    title: "Item",
                    body: stringify(itemValue),
                    sourceType: eventType,
                    isSidechain: isSidechain,
                    threadID: threadID
                )
            ]
        }

        let itemType = (normalizedText(item["type"]) ?? "item").lowercased()
        let entryKind: SessionTranscriptEntryKind = eventType == "item_started" ? .toolCall : .toolResult
        let toolUseID = extractToolUseID(from: item)

        switch itemType {
        case "commandexecution":
            return [
                makeEntry(
                    id: "\(messageID)-latest-command-\(eventType)",
                    role: .agent,
                    kind: entryKind,
                    title: eventType == "item_started" ? "Command Execution" : "Command Result",
                    body: stringify(item),
                    toolUseID: toolUseID,
                    sourceType: eventType,
                    toolName: "codexbash",
                    isSidechain: isSidechain,
                    threadID: threadID
                )
            ]
        case "filechange":
            return [
                makeEntry(
                    id: "\(messageID)-latest-file-change-\(eventType)",
                    role: .agent,
                    kind: entryKind,
                    title: eventType == "item_started" ? "File Changes" : "File Change Result",
                    body: stringify(item),
                    toolUseID: toolUseID,
                    sourceType: eventType,
                    toolName: "codexpatch",
                    isSidechain: isSidechain,
                    threadID: threadID
                )
            ]
        case "mcptoolcall":
            let toolName = normalizedText(item["tool"]) ?? normalizedText(item["server"]) ?? "MCP Tool"
            return [
                makeEntry(
                    id: "\(messageID)-latest-mcp-\(eventType)",
                    role: .agent,
                    kind: entryKind,
                    title: eventType == "item_started" ? toolDisplayName(toolName) : "\(toolDisplayName(toolName)) Result",
                    body: stringify(item),
                    toolUseID: toolUseID,
                    sourceType: eventType,
                    toolName: toolName,
                    isSidechain: isSidechain,
                    threadID: threadID
                )
            ]
        default:
            return [
                makeEntry(
                    id: "\(messageID)-latest-item-\(eventType)",
                    role: .agent,
                    kind: .raw,
                    title: "Item \(itemType)",
                    body: stringify(item),
                    sourceType: eventType,
                    isSidechain: isSidechain,
                    threadID: threadID
                )
            ]
        }
    }
}
