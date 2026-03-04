import Foundation
import CoreKit

extension SessionTranscriptPresentationBuilder {
    private static let entryBodyLimit = 8_000
    private static let ansiEscapePattern = "\u{001B}\\[[0-9;?]*[ -/]*[@-~]"
    private static let ansiEscapeRegex = try? NSRegularExpression(pattern: ansiEscapePattern)
    private static let removableControlCharacters: CharacterSet = {
        var set = CharacterSet.controlCharacters
        set.remove(charactersIn: "\n\t")
        return set
    }()

    static func parseEntries(
        payloadString: String?,
        messageID: String
    ) -> [SessionTranscriptEntry] {
        guard let payloadString, !payloadString.isEmpty else {
            return [
                makeEntry(
                    id: "\(messageID)-raw",
                    role: .system,
                    kind: .raw,
                    title: "Empty payload",
                    body: "No message content"
                )
            ]
        }

        guard let jsonData = payloadString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: jsonData) else {
            return [
                makeEntry(
                    id: "\(messageID)-raw",
                    role: .system,
                    kind: .raw,
                    title: "Raw payload",
                    body: payloadString
                )
            ]
        }

        guard let dictionary = object as? [String: Any] else {
            return [
                makeEntry(
                    id: "\(messageID)-raw",
                    role: .system,
                    kind: .raw,
                    title: "Raw payload",
                    body: stringify(object)
                )
            ]
        }

        let role = (dictionary["role"] as? String)?.lowercased()
        switch role {
        case "user":
            return parseUserRecord(dictionary, messageID: messageID)
        case "agent":
            return parseAgentRecord(dictionary, messageID: messageID)
        default:
            return [
                makeEntry(
                    id: "\(messageID)-raw",
                    role: .system,
                    kind: .raw,
                    title: "Unknown role",
                    body: stringify(dictionary)
                )
            ]
        }
    }

    private static func parseUserRecord(
        _ record: [String: Any],
        messageID: String
    ) -> [SessionTranscriptEntry] {
        if let contentArray = record["content"] as? [Any], !contentArray.isEmpty {
            let entries = parseUserContentArray(contentArray, messageID: messageID)
            if !entries.isEmpty {
                return entries
            }
        }

        guard let content = record["content"] as? [String: Any] else {
            if let text = normalizedText(record["content"]) {
                return [
                    makeEntry(
                        id: "\(messageID)-user",
                        role: .user,
                        kind: .text,
                        title: nil,
                        body: text
                    )
                ]
            }
            return [
                makeEntry(
                    id: "\(messageID)-user",
                    role: .user,
                    kind: .text,
                    title: nil,
                    body: stringify(record["content"])
                )
            ]
        }

        if let nestedContentArray = content["content"] as? [Any], !nestedContentArray.isEmpty {
            let entries = parseUserContentArray(nestedContentArray, messageID: messageID)
            if !entries.isEmpty {
                return entries
            }
        }

        if let type = (content["type"] as? String)?.lowercased() {
            switch type {
            case "text", "input_text":
                let text =
                    normalizedText(content["text"]) ??
                    normalizedText(content["input_text"]) ??
                    extractMessageText(from: content["content"]) ??
                    stringify(content)
                return [
                    makeEntry(
                        id: "\(messageID)-user",
                        role: .user,
                        kind: .text,
                        title: nil,
                        body: text
                    )
                ]
            case "image", "input_image", "image_url":
                return [
                    makeEntry(
                        id: "\(messageID)-user-image-0",
                        role: .user,
                        kind: .text,
                        title: nil,
                        body: imagePlaceholderText(index: 1)
                    )
                ]
            default:
                break
            }
        }

        if let text =
            extractMessageText(from: content["text"]) ??
            extractMessageText(from: content["message"]) ??
            extractMessageText(from: content["content"]) {
            return [
                makeEntry(
                    id: "\(messageID)-user",
                    role: .user,
                    kind: .text,
                    title: nil,
                    body: text
                )
            ]
        }

        return [
            makeEntry(
                id: "\(messageID)-user",
                role: .user,
                kind: .raw,
                title: "User payload",
                body: stringify(content)
            )
        ]
    }

    private static func parseAgentRecord(
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
            case "text":
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
            case "thinking":
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
                if let toolUseID {
                    toolNamesByID[toolUseID] = name
                }
                let inputText = stringify(chunk["input"])
                entries.append(
                    makeEntry(
                        id: "\(messageID)-assistant-\(index)",
                        role: .agent,
                        kind: .toolCall,
                        title: toolDisplayName(name),
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
                let title = linkedToolName.map { "\(toolDisplayName($0)) Result" } ?? "Tool result"
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
            let title = reasoningTitle ?? toolDisplayName(name)
            let body = reasoningTitle == nil
                ? stringify(dictionary["input"])
                : stringify(dictionary["input"])
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
            return [
                makeEntry(
                    id: "\(messageID)-acp-task",
                    role: .agent,
                    kind: .thinking,
                    title: nil,
                    body: "Thinking…",
                    sourceType: type,
                    isSidechain: isSidechain,
                    threadID: threadID
                )
            ]
        case "task_complete", "turn_aborted":
            return []
        case "token_count":
            return []
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

    private static func makeEntry(
        id: String,
        role: SessionTranscriptEntryRole,
        kind: SessionTranscriptEntryKind,
        title: String?,
        body: String,
        toolUseID: String? = nil,
        sourceType: String? = nil,
        preserveWhitespace: Bool = false,
        toolName: String? = nil,
        isSidechain: Bool = false,
        threadID: String? = nil
    ) -> SessionTranscriptEntry {
        let cleanedBody = sanitizeText(body)
        let normalizedBody: String = {
            if preserveWhitespace {
                if cleanedBody.isEmpty {
                    return " "
                }
                return trimBody(cleanedBody)
            }
            let trimmed = cleanedBody.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? " " : trimBody(trimmed)
        }()
        let cleanedTitle = title.map(sanitizeText)
        let cleanedSourceType = sourceType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedSourceType = cleanedSourceType?.isEmpty == false
            ? cleanedSourceType
            : nil
        let cleanedToolName = toolName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedToolName = cleanedToolName?.isEmpty == false
            ? cleanedToolName
            : nil
        let cleanedThreadID = threadID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedThreadID = cleanedThreadID?.isEmpty == false
            ? cleanedThreadID
            : nil
        return SessionTranscriptEntry(
            id: id,
            role: role,
            kind: kind,
            title: cleanedTitle,
            body: normalizedBody,
            toolUseID: toolUseID,
            sourceType: normalizedSourceType,
            toolName: normalizedToolName,
            isSidechain: isSidechain,
            threadID: normalizedThreadID
        )
    }

    private static func extractIsSidechain(from dictionary: [String: Any]) -> Bool {
        if let explicit = dictionary["isSidechain"] as? Bool, explicit {
            return true
        }
        if let explicit = dictionary["sidechain"] as? Bool, explicit {
            return true
        }
        return normalizedText(dictionary["parent_tool_use_id"]) != nil ||
            normalizedText(dictionary["parentToolUseId"]) != nil
    }

    private static func extractThreadID(from dictionary: [String: Any]) -> String? {
        return normalizedText(dictionary["thread_id"]) ??
            normalizedText(dictionary["threadId"]) ??
            normalizedText(dictionary["session_id"]) ??
            normalizedText(dictionary["sessionId"])
    }

    private static func extractToolUseID(from dictionary: [String: Any]) -> String? {
        let candidates: [Any?] = [
            dictionary["tool_use_id"],
            dictionary["toolUseId"],
            dictionary["callId"],
            dictionary["id"],
        ]
        for candidate in candidates {
            if let text = normalizedText(candidate) {
                return text
            }
        }
        return nil
    }

    static func shouldDisplay(entry: SessionTranscriptEntry) -> Bool {
        let hasTitle = !(entry.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasBody = !entry.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasTitle || hasBody
    }

    private static func trimBody(_ value: String) -> String {
        guard value.count > entryBodyLimit else { return value }
        return String(value.prefix(entryBodyLimit)) + "\n…"
    }

    private static func normalizedText(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let text = value as? String {
            let cleaned = sanitizeText(text)
            let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func stringifyToolResultContent(_ value: Any?) -> String {
        if let string = extractMessageText(from: value) {
            return string
        }
        if let chunks = value as? [[String: Any]] {
            let texts = chunks.compactMap { chunk -> String? in
                guard (chunk["type"] as? String) == "text" else { return nil }
                return normalizedText(chunk["text"])
            }
            if !texts.isEmpty {
                return texts.joined(separator: "\n")
            }
        }
        return stringify(value)
    }

    private static func shouldHideToolResult(_ value: Any?) -> Bool {
        guard let object = value as? [String: Any] else { return false }
        let status = normalizedText(object["status"])?.lowercased()
        let contentText = extractMessageText(from: object["content"])
        if status == "completed", contentText == nil {
            return true
        }
        return false
    }

    private static func codexReasoningTitle(from value: Any?) -> String? {
        guard let object = value as? [String: Any] else { return nil }
        guard let title = normalizedText(object["title"]) else { return nil }
        return title
    }

    private static func parseUserContentArray(
        _ contentArray: [Any],
        messageID: String
    ) -> [SessionTranscriptEntry] {
        var entries: [SessionTranscriptEntry] = []
        entries.reserveCapacity(contentArray.count)
        var imageIndex = 0

        for (index, item) in contentArray.enumerated() {
            guard let chunk = item as? [String: Any] else {
                if let text = normalizedText(item) {
                    entries.append(
                        makeEntry(
                            id: "\(messageID)-user-\(index)",
                            role: .user,
                            kind: .text,
                            title: nil,
                            body: text
                        )
                    )
                } else {
                    entries.append(
                        makeEntry(
                            id: "\(messageID)-user-\(index)",
                            role: .user,
                            kind: .raw,
                            title: "Chunk",
                            body: stringify(item)
                        )
                    )
                }
                continue
            }

            let type = (normalizedText(chunk["type"]) ?? "").lowercased()
            switch type {
            case "text", "input_text":
                let text =
                    normalizedText(chunk["text"]) ??
                    normalizedText(chunk["input_text"]) ??
                    extractMessageText(from: chunk["content"]) ??
                    stringify(chunk)
                entries.append(
                    makeEntry(
                        id: "\(messageID)-user-\(index)",
                        role: .user,
                        kind: .text,
                        title: nil,
                        body: text
                    )
                )
            case "image", "input_image", "image_url":
                imageIndex += 1
                entries.append(
                    makeEntry(
                        id: "\(messageID)-user-\(index)",
                        role: .user,
                        kind: .text,
                        title: nil,
                        body: imagePlaceholderText(index: imageIndex)
                    )
                )
            default:
                if type.contains("image") {
                    imageIndex += 1
                    entries.append(
                        makeEntry(
                            id: "\(messageID)-user-\(index)",
                            role: .user,
                            kind: .text,
                            title: nil,
                            body: imagePlaceholderText(index: imageIndex)
                        )
                    )
                    continue
                }

                if let text =
                    extractMessageText(from: chunk["text"]) ??
                    extractMessageText(from: chunk["message"]) ??
                    extractMessageText(from: chunk["content"]) {
                    entries.append(
                        makeEntry(
                            id: "\(messageID)-user-\(index)",
                            role: .user,
                            kind: .text,
                            title: nil,
                            body: text
                        )
                    )
                } else {
                    entries.append(
                        makeEntry(
                            id: "\(messageID)-user-\(index)",
                            role: .user,
                            kind: .raw,
                            title: type.isEmpty ? "Chunk" : "Chunk \(type)",
                            body: stringify(chunk)
                        )
                    )
                }
            }
        }

        return entries
    }

    private static func imagePlaceholderText(index: Int) -> String {
        "[Image #\(max(1, index))]"
    }

    private static func sanitizeText(_ value: String) -> String {
        var cleaned = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        if let regex = ansiEscapeRegex {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                options: [],
                range: range,
                withTemplate: ""
            )
        }

        let scalars = cleaned.unicodeScalars.filter { scalar in
            !removableControlCharacters.contains(scalar)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func extractMessageText(from value: Any?) -> String? {
        guard let value else { return nil }
        if let text = normalizedText(value) {
            return text
        }
        if let dictionary = value as? [String: Any] {
            let directCandidates: [Any?] = [
                dictionary["text"],
                dictionary["message"],
                dictionary["delta"],
                dictionary["content"],
                dictionary["output"],
            ]
            for candidate in directCandidates {
                if let extracted = extractMessageText(from: candidate) {
                    return extracted
                }
            }
            return nil
        }
        if let array = value as? [Any] {
            let parts = array.compactMap { extractMessageText(from: $0) }
            if !parts.isEmpty {
                return parts.joined(separator: "\n")
            }
        }
        return nil
    }

    private static func toolDisplayName(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Tool" }
        let key = trimmed
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")

        switch key {
        case "read", "readfile", "readfiles":
            return "Read Files"
        case "write", "writefile", "writefiles", "edit", "applypatch", "codexpatch", "patch":
            return "Edit Files"
        case "bash", "codexbash", "execcommand", "terminal", "shell":
            return "Run Command"
        case "listdirectory", "getdirectorytree", "ls":
            return "List Files"
        case "ripgrep", "rg", "grep", "search":
            return "Search Files"
        case "difftastic", "diff":
            return "View Diff"
        case "task":
            return "Run Task"
        case "webfetch":
            return "Fetch Web"
        case "codexreasoning":
            return "Reasoning"
        default:
            return humanizedIdentifier(trimmed)
        }
    }

    private static func humanizedIdentifier(_ value: String) -> String {
        let separatorsNormalized = value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let withCamelSpacing = separatorsNormalized.replacingOccurrences(
            of: "([a-z0-9])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        )
        let collapsed = withCamelSpacing
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return "Tool" }
        return collapsed
            .split(separator: " ")
            .map { token in
                let lower = token.lowercased()
                return lower.prefix(1).uppercased() + String(lower.dropFirst())
            }
            .joined(separator: " ")
    }

    private static func stringify(_ value: Any?) -> String {
        guard let value else { return "null" }
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
    }
}
